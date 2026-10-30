;; Egress sandbox for the agent subprocess.
;;
;; The agent, and everything it spawns, runs in a network namespace with no route
;; out. The only way to reach the network is a CONNECT proxy on a unix socket, which
;; allows just the hosts the profile lists and logs every attempt, allowed or denied.
;; An agent that ignores HTTPS_PROXY does not leak, it fails.
;;
;; A profile's :sandbox field is one of:
;;   false (or absent)                 run unsandboxed
;;   true                             sandbox, no host allowed
;;   {:net false}                     sandbox, no network at all
;;   {:net :proxy :allow [HOST:PORT]}  sandbox, egress only to those hosts
;; plus :read and :write, extra $HOME paths to expose read-only or writable, and
;; :mask, extra paths to hide inside the sandbox. The docker and D-Bus sockets are
;; masked by default: without that the agent can ask a daemon outside the namespace
;; to make the request for it. :mask false leaves them alone.
;;
;; The filesystem is scoped too. The host is read-only, but $HOME is not the host's:
;; inside the namespace it is replaced with an empty directory, and then only an
;; allowlist of $HOME paths is bound back in — the toolchain state in home-readable
;; below plus whatever :read adds. So ~/.ssh, ~/.aws, ~/.config/gh and ~/.kube are not
;; read-only, they are absent, and there is no denylist to keep up to date: a path a
;; tool needs is one more line in :read. The writable places are the project the
;; session runs in, /tmp, the XDG data home and cache, the paths in home-writable, and
;; whatever :write adds — except the project's .git/hooks, .git/config and
;; .gitattributes, which stay read-only even though the project is writable: a hook,
;; a core.hooksPath or a filter driver written there would run on the host, outside
;; the sandbox, the next time you use git. The cost is that git config writes fail
;; inside a session; see project-readonly.
;;
;; bwrap does the namespace; bin/acp-egress.py is the proxy (host side) and the
;; 127.0.0.1 bridge into the namespace (sandbox side, which then execs the agent).
;;
;; The proxy writes what it allowed and refused to vim.g.acp-egress-log-dir
;; (stdpath("log") by default), and a refused host is also said once in the chat.
;; This stops IP traffic from the agent and everything it spawns. It does not stop a
;; unix socket, which is why the daemons above are masked. Needs bwrap and python3.
;;
;; A profile's :sandbox is the policy and the default; :Acp sandbox and :Acp nosandbox
;; turn it on or off for one session, without touching the profile.

(local listen "127.0.0.1:8899")
(local defaults ["/var/run/docker.sock" "/run/docker.sock"])
(var counter 0)

;; The $HOME paths a sandboxed agent may still read. Everything else in $HOME is
;; absent rather than read-only, so the secrets need no denylist entry: ~/.ssh,
;; ~/.aws, ~/.config/gh, ~/.kube, ~/.docker/config.json and ~/.netrc are simply not
;; there. A directory listed here is exposed whole, so name the subdirectory a tool
;; reads where the parent also holds credentials — .m2/repository, not .m2.
(local home-readable
  [".gitconfig" ".editorconfig" ".inputrc"
   ".cargo" ".rustup"
   ".node-gyp" ".nvm" ".bun" ".deno" ".pyenv"
   ".m2/repository"
   ".gradle/caches" ".gradle/wrapper"
   ".lein" ".clojure" ".clj-kondo"
   ".local/bin"
   ".config/git"
   ;; Agents keep their own configuration and credentials under $HOME; hiding them
   ;; would only stop the agent from authenticating, which isn't what this is for.
   ".config/opencode" ".claude" ".claude.json"])

;; Writable from the start: every tool writes them and none is a credential store.
;; .claude/projects is where Claude Code keeps its session transcripts, which
;; session/list and session/load read back; without it a sandboxed session can't be
;; resumed. Only that subdirectory: the rest of .claude holds settings and hooks the
;; host's claude would run, so it stays read-only.
(local home-writable [".npm" ".cache" ".local/state" ".claude/projects"])

;; Project paths kept read-only even though the project itself is writable. A git
;; hook is the sharpest one: the agent could write one and it would run on the host,
;; outside the sandbox, the next time you commit. The config and the attributes file
;; are the same class of problem — core.hooksPath, core.fsmonitor, core.pager,
;; alias.!cmd, credential.helper, diff.external and filter drivers all name commands
;; git runs for you — so they stay visible but immutable too.
(local project-readonly [".git/hooks" ".git/config" ".gitattributes"])

(fn available? []
  (not= "" (vim.fn.exepath "bwrap")))

(fn normalize [spec]
  ;; A profile's :sandbox -> nil (off) or
  ;; {:net :proxy :allow [...] :read [...] :write [...] :mask ...}.
  (if (or (= spec nil) (= spec false))
    nil
    (= spec true)
    {:net :proxy :allow [] :read [] :write [] :mask nil}
    (= (type spec) :table)
    (let [read (vim.deepcopy (or spec.read []))
          write (vim.deepcopy (or spec.write []))]
      (if (= spec.net false)
        {:net false :read read :write write :mask spec.mask}
        {:net :proxy
         :allow (vim.deepcopy (or spec.allow []))
         :read read
         :write write
         :mask spec.mask}))))

(fn home []
  ;; $HOME as an absolute path, or nil when there is none worth masking.
  (let [path vim.env.HOME]
    (when (and path
               (= (string.sub path 1 1) "/")
               (not= path "/"))
      (vim.fs.normalize path))))

(fn home-path [entry]
  ;; An allowlist entry: absolute, ~-prefixed, or relative to $HOME.
  (let [h (home)
        home-relative (string.sub entry 1 2)]
    (if (= (string.sub entry 1 1) "/")
      (vim.fs.normalize entry)
      (when h
        (vim.fs.normalize
          (if (= home-relative "~/")
            (.. h (string.sub entry 2))
            (.. h "/" entry)))))))

(fn allowlist [defaults given]
  ;; The entries that exist, resolved and without repeats: binding one that is not
  ;; there is a sandbox that fails to start rather than one that is merely stricter.
  (let [seen {}]
    (icollect [_ entry (ipairs (vim.list_extend (vim.deepcopy defaults) (or given [])))]
      (let [path (home-path entry)]
        (when (and path (not= "" (vim.fn.getftype path)) (not (. seen path)))
          (tset seen path true)
          path)))))

(fn describe [spec]
  ;; A short phrase for the chat and the log.
  (let [s (normalize spec)]
    (if (not s) "unsandboxed"
        (= s.net false) "no network"
        (= 0 (length s.allow)) "no host allowed"
        (.. "egress to " (table.concat s.allow ", ")))))

(fn script []
  (.. (vim.fn.stdpath :config) "/bin/acp-egress.py"))

(fn python []
  (let [exe (vim.fn.exepath "python3")]
    (if (= exe "") nil exe)))

(fn data-dir []
  ;; The XDG data home itself, not Neovim's nvim subdirectory of it: agents keep
  ;; their state beside it, not inside it. Empty XDG_DATA_HOME means the default.
  (let [xdg vim.env.XDG_DATA_HOME]
    (vim.fs.normalize (if (and xdg (not= xdg ""))
                          xdg
                          (.. (or vim.env.HOME "/") "/.local/share")))))

(fn strip-slash [path]
  (if (and (> (length path) 1) (= (string.sub path -1) "/"))
    (string.sub path 1 -2)
    path))

(fn encloses? [parent path]
  ;; parent is path, or a directory path is in.
  (let [p (strip-slash (vim.fs.normalize parent))
        c (strip-slash (vim.fs.normalize path))]
    (or (= p c)
        (= (string.sub c 1 (+ (length p) 1)) (.. p "/")))))

(fn runtime-dir []
  (let [(ok run) (pcall vim.fn.stdpath :run)
        base (if (and ok (= (type run) :string) (not= run ""))
               run
               (vim.fn.stdpath :cache))]
    (.. base "/acp")))

(fn mask-paths [spec]
  ;; Paths to hide: the daemons that could egress on the agent's behalf, and the
  ;; keyring store the writable data home would otherwise expose. Symlinks are
  ;; resolved, as $XDG_RUNTIME_DIR/bus often is one: masking only the link would
  ;; leave the socket's real path open.
  (let [user (if (= (type spec.mask) :table) spec.mask [])
        base (if (= spec.mask false) [] defaults)
        runtime vim.env.XDG_RUNTIME_DIR
        runtime-extra (if runtime
                        [(.. runtime "/bus")
                         (.. runtime "/systemd/private")
                         (.. runtime "/docker.sock")
                         (.. runtime "/podman/podman.sock")]
                        [])
        h (home)
        home-extra (if h [(.. h "/.local/share/keyrings")] [])
        all (vim.list_extend
              (vim.list_extend (vim.deepcopy base) runtime-extra)
              (vim.list_extend user home-extra))
        seen {}]
    (icollect [_ path (ipairs all)]
      (let [real (or (vim.uv.fs_realpath path) path)]
        (when (and (not (. seen real)) (not= "" (vim.fn.getftype real)))
          (tset seen real true)
          real)))))

(fn bwrap-prefix [spec project]
  ;; The namespace, the masks, then the relay that execs whatever follows. The host
  ;; is bound read-only, so the agent can run everything it finds but change nothing.
  (let [h (home)
        ro (allowlist home-readable spec.read)
        rw (allowlist home-writable spec.write)
        argv ["bwrap"
              "--unshare-net" "--unshare-pid" "--unshare-ipc" "--unshare-uts"
              "--new-session" "--die-with-parent"
              ;; Everything from the host, read-only, then a writable /dev and a
              ;; procfs for the new pid namespace.
              "--ro-bind" "/" "/"
              "--dev-bind" "/dev" "/dev"
              "--proc" "/proc"
              ;; Needed only to bring loopback up, which the relay does first.
              "--cap-add" "CAP_NET_ADMIN"]]
    (when h
      ;; $HOME is emptied first, so a path that is not in the allowlist can't be read
      ;; because it isn't there — that is what keeps ~/.ssh and ~/.aws out without
      ;; naming them. Then the allowlist is bound back in.
      (vim.list_extend argv ["--tmpfs" h])
      (each [_ path (ipairs ro)]
        (vim.list_extend argv ["--ro-bind" path path]))
      (each [_ path (ipairs rw)]
        (vim.list_extend argv ["--bind-try" path path]))
      ;; The relay lives under $HOME and has to be put back after the masking.
      (let [relay (script)]
        (when (= (string.sub relay 1 (+ (length h) 1)) (.. h "/"))
          (vim.list_extend argv ["--ro-bind" relay relay]))))
    (vim.list_extend
      argv
      [;; The only writable places besides the allowlist: the project, /tmp, and the
       ;; XDG data home, so an agent can keep its own state.
       "--bind-try" project project
       "--bind-try" (data-dir) (data-dir)
       "--bind" "/tmp" "/tmp"])
    ;; Mounted after the project, so read-only wins over its writable bind: a path the
    ;; profile asked to be read-only is not made writable again by running in it, and
    ;; a hook or a line of repo config can't be replaced with one that runs on the
    ;; host later. Files and directories alike.
    (each [_ path (ipairs ro)]
      (when (and (encloses? project path)
                 (not= (strip-slash path) (strip-slash project)))
        (vim.list_extend argv ["--ro-bind" path path])))
    (each [_ rel (ipairs project-readonly)]
      (let [path (vim.fs.joinpath project rel)]
        (when (not= "" (vim.fn.getftype path))
          (vim.list_extend argv ["--ro-bind" path path]))))
    ;; A submodule's git directory lives under .git/modules, so its hooks are not
    ;; covered by the project's .git/hooks and are mounted the same way.
    (each [_ path (ipairs (vim.fn.glob (vim.fs.joinpath project ".git/modules/**/hooks")
                                       true true))]
      (vim.list_extend argv ["--ro-bind" path path]))
    ;; In a worktree or a submodule .git is a file naming the real git directory. It is
    ;; writable inside the project, and pointing it at a directory the agent created
    ;; would make the host read the configuration written there, so it is frozen. The
    ;; directory case is left alone: git has to write .git to work at all.
    (let [dotgit (vim.fs.joinpath project ".git")
          kind (vim.fn.getftype dotgit)]
      (when (and (not= "" kind) (not= "dir" kind))
        (vim.list_extend argv ["--ro-bind" dotgit dotgit])))
    (each [_ path (ipairs (mask-paths spec))]
      ;; /dev/null can't be mounted on a directory, so a directory is hidden by an
      ;; empty tmpfs and a file or socket by binding /dev/null over it.
      (if (= "dir" (vim.fn.getftype path))
        (vim.list_extend argv ["--tmpfs" path])
        (vim.list_extend argv ["--ro-bind" "/dev/null" path])))
    argv))

(fn proxy-env []
  ;; Loopback is the sandbox's own, not the host's: the agent's local API (opencode
  ;; serves one on an ephemeral port) must not be sent to the proxy, which could only
  ;; reach the host's loopback. Everything else goes through the proxy by name; the
  ;; agent has no resolver. Any proxy inherited from the parent is stripped first, in
  ;; transport.
  {:HTTP_PROXY (.. "http://" listen)
   :http_proxy (.. "http://" listen)
   :HTTPS_PROXY (.. "http://" listen)
   :https_proxy (.. "http://" listen)
   :NO_PROXY "localhost,127.0.0.1,::1"
   :no_proxy "localhost,127.0.0.1,::1"
   ;; Node's fetch only looks at the environment with this set.
   :NODE_USE_ENV_PROXY "1"})

(fn proxy-argv [sock log allow]
  (let [argv [(python) (script) "serve" "--socket" sock "--log" log]]
    (each [_ host (ipairs allow)]
      (vim.list_extend argv ["--allow" host]))
    argv))

(fn log-path []
  (vim.fn.expand (or vim.g.acp-egress-log-dir (vim.fn.stdpath :log))))

(fn prepare [spec project]
  ;; Start the proxy if the spec needs one, and return what transport.start needs:
  ;; {:prefix [ARGV...] :env {VAR VALUE} :proc proxy :sock :log :net :allow :watch nil}.
  ;; project is the directory the session runs in, the one writable place besides /tmp.
  ;; Returns nil and a message when the sandbox can't be built.
  (let [s (normalize spec)
        ;; bwrap resolves a relative destination against the sandbox root, so a project
        ;; of "." would bind the project over / and every mask after it would be made
        ;; in the host's project directory. Resolve it the way vim.system resolves the
        ;; agent's cwd.
        project (when (and project (not= project ""))
                  (strip-slash (vim.fs.normalize (vim.fn.fnamemodify project ":p"))))]
    (if (not s)
      nil
      (not project)
      (values nil "the project directory is not known")
      ;; Binding the project writable would put $HOME back if the session runs in it,
      ;; so refuse rather than start a sandbox that hides nothing.
      (and (home) (encloses? project (home)))
      (values nil "the project is $HOME, so binding it writable would undo the sandbox")
      (not (available?))
      (values nil "bwrap is not installed")
      (not (python))
      (values nil "python3 is not installed")
      (= s.net false)
      {:prefix (vim.list_extend (bwrap-prefix s project) ["--"])
       :env {}
       :net false
       :allow []
       :proc nil}
      (let [n (+ counter 1)
            _ (set counter n)
            dir (runtime-dir)
            sock (.. dir "/" (vim.fn.getpid) "-" n ".sock")
            log (.. (log-path) "/acp-egress-" (vim.fn.getpid) "-" n ".log")
            ;; The runtime directory is on a tmpfs, so it is gone after a reboot and
            ;; the proxy would fail to bind its socket.
            _mkdir-dir (vim.fn.mkdir dir "p")
            _mkdir (vim.fn.mkdir (vim.fn.fnamemodify log ":h") "p")
            (ok proc) (pcall vim.system (proxy-argv sock log s.allow) {})]
        (if (not ok)
          (values nil (.. "could not start the egress proxy: " (tostring proc)))
          (if (not (vim.wait 2000 #(= "socket" (?. (vim.uv.fs_stat sock) :type))))
            (do
              (pcall #(proc:kill :sigterm))
              (values nil (.. "the egress proxy did not start — see " log)))
            {:prefix (vim.list_extend (bwrap-prefix s project)
                                      ["--" (python) (script) "relay"
                                       "--socket" sock "--listen" listen "--log" log "--"])
             :env (proxy-env)
             :net :proxy
             :allow s.allow
             :proc proc
             :sock sock
             :log log
             :watch nil
             :partial ""
             :offset 0}))))))

(fn read-new [box]
  ;; Timestamped log lines the proxy wrote since the last call.
  (let [f (io.open box.log :r)]
    (if (not f)
      []
      (do
        (f:seek :set box.offset)
        (let [chunk (or (f:read "*a") "")
              text (.. box.partial chunk)
              parts (vim.split text "\n" {:plain true})]
          (set box.offset (+ box.offset (length chunk)))
          (set box.partial (table.remove parts))
          (f:close)
          (icollect [_ line (ipairs parts)]
            ;; "TIME KIND host:port[ METHOD [URL]]" -> the host is what the chat names,
            ;; so one refused host is one line however many URLs it tried.
            (let [(kind rest) (string.match line "^%S+ (%u+) (.*)$")]
              (when kind
                {:kind kind
                 :host (string.match rest "^%S+")
                 :method (string.match rest "^%S+ (%S+)")
                 :what rest}))))))))

(fn watch [box on-line]
  ;; Report what the proxy logs while the session runs.
  (when (and box box.log)
    (let [timer (vim.uv.new_timer)]
      (timer:start 0 1000
                   (vim.schedule_wrap
                     (fn []
                       (each [_ entry (ipairs (read-new box))]
                         (pcall on-line entry)))))
      (set box.watch timer))))

(fn stop [box]
  (when box
    (when box.watch
      (box.watch:stop)
      (box.watch:close)
      (set box.watch nil))
    (when box.proc
      (pcall #(box.proc:kill :sigterm))
      (set box.proc nil))
    (when box.sock
      (pcall vim.fn.delete box.sock)
      (set box.sock nil))))

{: available?
 : normalize
 : describe
 : prepare
 : watch
 : stop
 : read-new
 : script
 : data-dir}
