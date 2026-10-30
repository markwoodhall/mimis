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
;; plus :mask, extra paths to hide inside the sandbox. The docker and D-Bus sockets
;; are masked by default: without that the agent can ask a daemon outside the
;; namespace to make the request for it. :mask false leaves them alone.
;;
;; The filesystem is scoped too: the agent sees the host read-only, and may write
;; only to the project directory the session runs in, to /tmp, and to the XDG data
;; directory, where agents keep their own state.
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

(fn available? []
  (not= "" (vim.fn.exepath "bwrap")))

(fn normalize [spec]
  ;; A profile's :sandbox -> nil (off) or {:net :proxy :allow [...] :mask [...]}.
  (if (or (= spec nil) (= spec false))
    nil
    (= spec true)
    {:net :proxy :allow []}
    (= (type spec) :table)
    (if (= spec.net false)
      {:net false}
      {:net :proxy
       :allow (vim.deepcopy (or spec.allow []))
       :mask spec.mask})))

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

(fn runtime-dir []
  (let [(ok run) (pcall vim.fn.stdpath :run)
        base (if (and ok (= (type run) :string) (not= run ""))
               run
               (vim.fn.stdpath :cache))]
    (.. base "/acp")))

(fn mask-paths [spec]
  ;; Paths to bind /dev/null over: the daemons that could egress on the agent's behalf.
  ;; Symlinks are resolved, as $XDG_RUNTIME_DIR/bus often is one: masking only the
  ;; link would leave the socket's real path open.
  (let [user (if (= (type spec.mask) :table) spec.mask [])
        base (if (= spec.mask false) [] defaults)
        runtime vim.env.XDG_RUNTIME_DIR
        extra (when runtime
                [(.. runtime "/bus")
                 (.. runtime "/systemd/private")
                 (.. runtime "/docker.sock")
                 (.. runtime "/podman/podman.sock")])
        seen {}]
    (icollect [_ path (ipairs (vim.list_extend (vim.deepcopy base) (or extra [])))]
      (let [real (or (vim.uv.fs_realpath path) path)]
        (when (and (not (. seen real)) (not= "" (vim.fn.getftype real)))
          (tset seen real true)
          real)))))

(fn bwrap-prefix [spec project]
  ;; The namespace, the masks, then the relay that execs whatever follows. The host
  ;; is bound read-only, so the agent can run everything it finds but change
  ;; nothing; its writes are the project directory and /tmp.
  (let [argv ["bwrap"
              "--unshare-net" "--unshare-pid" "--unshare-ipc" "--unshare-uts"
              "--new-session" "--die-with-parent"
              ;; Everything from the host, read-only, then a writable /dev and a
              ;; procfs for the new pid namespace.
              "--ro-bind" "/" "/"
              "--dev-bind" "/dev" "/dev"
              "--proc" "/proc"
              ;; Needed only to bring loopback up, which the relay does first.
              "--cap-add" "CAP_NET_ADMIN"
              ;; The only writable paths: the project, /tmp, and the XDG data
              ;; home, so an agent can keep its own state.
              "--bind-try" project project
              "--bind-try" (data-dir) (data-dir)
              "--bind" "/tmp" "/tmp"]]
    (each [_ path (ipairs (mask-paths spec))]
      (vim.list_extend argv ["--ro-bind" "/dev/null" path]))
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
  (let [s (normalize spec)]
    (if (not s)
      nil
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
