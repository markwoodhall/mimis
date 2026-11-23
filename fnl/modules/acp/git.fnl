;; A worktree for a thread, and how its work lands.
;;
;; :Acp worktree starts the session in a worktree of its own, on a branch of its own,
;; so the agent's changes never touch your checkout: the worktree is
;; <repo>/.acp/worktrees/<id> (vim.g.acp-worktree-dir changes the directory) and the
;; branch <project>/<id>, made from the repo's default branch, or from the branch of
;; the thread it was started from, so a thread forked from another builds on it. The
;; untracked files .worktreeinclude names (gitignore patterns; .mcp.json and
;; .claude/settings.local.json without one) are copied in, as a checkout of what's
;; committed has none of them.
;;
;; Landing is how the agent is told to finish, in its first prompt (:AcpLand changes it
;; later, told in the next one): pr (the default) commits, pushes and opens a PR/MR with
;; the forge CLI; main merges fast-forward into the main checkout, which the sandbox
;; opens to it for that; none commits and leaves the rest to you. vim.g.acp-landing
;; changes the default. The base and landing are kept in the repo's config, under the
;; branch, so a resumed thread keeps them.
;;
;; A worktree whose work is all committed can be freed (W in :AcpThreads, or
;; :AcpFreeWorktrees): the directory goes, the branch stays until it's merged.

(local default-includes [".mcp.json" ".claude/settings.local.json"])

(fn run [cwd args]
  ;; Runs git in cwd and waits: ok?, stdout, stderr, all trimmed.
  (let [(ok result) (pcall #(: (vim.system (vim.list_extend ["git" "-C" cwd] args) {:text true})
                               :wait))]
    (if ok
      (values (= result.code 0) (vim.trim (or result.stdout "")) (vim.trim (or result.stderr "")))
      (values false "" (tostring result)))))

(fn repo-of [dir]
  ;; The main checkout of the repository dir is in, worktree or not: the directory
  ;; holding the common git directory. nil outside a repository.
  (let [(ok out) (run dir ["rev-parse" "--path-format=absolute" "--git-common-dir"])]
    (when (and ok (not= out ""))
      (let [common (vim.fs.normalize out)]
        (if (= ".git" (vim.fs.basename common))
          (vim.fs.dirname common)
          ;; A bare repository: there is no checkout to land in, so its worktrees are
          ;; their own repo.
          (let [(ok top) (run dir ["rev-parse" "--show-toplevel"])]
            (when ok (vim.fs.normalize top))))))))

(fn toplevel [dir]
  (let [(ok out) (run dir ["rev-parse" "--show-toplevel"])]
    (when (and ok (not= out "")) (vim.fs.normalize out))))

(fn branch-of [dir]
  (let [(ok out) (run dir ["branch" "--show-current"])]
    (when (and ok (not= out "")) out)))

(fn worktree? [dir]
  ;; A linked worktree's .git is a file naming its git directory.
  (= "file" (vim.fn.getftype (vim.fs.joinpath dir ".git"))))

(fn worktree-dir [repo]
  (vim.fs.normalize (vim.fn.expand (or vim.g.acp-worktree-dir (vim.fs.joinpath repo ".acp/worktrees")))))

(var ids 0)

(fn short-id [dir]
  ;; Eight hex digits no worktree in dir has: from the clock and this process, as
  ;; math.random repeats its sequence in every Neovim.
  (var id nil)
  (while (or (not id) (not= "" (vim.fn.getftype (vim.fs.joinpath dir id))))
    (set ids (+ ids 1))
    (set id (string.sub (vim.fn.sha256 (.. (vim.uv.hrtime) ":" (vim.fn.getpid) ":" ids)) 1 8)))
  id)

(fn branch-prefix [repo]
  ;; The project's name as git takes it in a ref: anything else becomes a dash.
  (let [name (-> (vim.fs.basename repo)
                 (string.gsub "[^%w%.%-_]" "-")
                 (string.gsub "^[%.%-]+" "")
                 (string.gsub "%.lock$" ""))]
    (if (= name "") "thread" name)))

(fn config-get [repo branch key]
  (let [(ok out) (run repo ["config" "--get" (.. "branch." branch "." key)])]
    (when (and ok (not= out "")) out)))

(fn config-set [repo branch key value]
  (run repo ["config" (.. "branch." branch "." key) value]))

(fn default-base [repo]
  ;; The branch new worktrees start from: what origin calls its default, else the
  ;; checkout's own branch, else HEAD.
  (let [(ok out) (run repo ["symbolic-ref" "--short" "refs/remotes/origin/HEAD"])]
    (or (when (and ok (not= out "")) (pick-values 1 (out:gsub "^origin/" "")))
        (branch-of repo)
        "HEAD")))

(fn landing-default []
  (let [given (tostring (or vim.g.acp-landing "pr"))]
    (if (or (= given "pr") (= given "main") (= given "none")) given "pr")))

(fn include-patterns [repo]
  (let [path (vim.fs.joinpath repo ".worktreeinclude")]
    (if (= 1 (vim.fn.filereadable path))
      (icollect [_ line (ipairs (vim.fn.readfile path))]
        (let [line (vim.trim line)]
          (when (and (not= line "") (not (vim.startswith line "#"))) line)))
      default-includes)))

(fn copy-includes [repo path]
  ;; The checkout's untracked files matching the patterns, into the worktree, unless
  ;; it has them already: the agent may have changed its own.
  (let [patterns (include-patterns repo)]
    (when (> (length patterns) 0)
      (let [args ["ls-files" "-z" "--others" "--ignored"]]
        (each [_ p (ipairs patterns)]
          (vim.list_extend args ["-x" p]))
        (let [(ok out) (run repo args)]
          (when ok
            (each [_ rel (ipairs (vim.split out "\0" {:plain true :trimempty true}))]
              (let [from (vim.fs.joinpath repo rel)
                    to (vim.fs.joinpath path rel)]
                (when (and (= "file" (vim.fn.getftype from)) (= "" (vim.fn.getftype to)))
                  (vim.fn.mkdir (vim.fs.dirname to) "p")
                  (vim.uv.fs_copyfile from to))))))))))

(fn inspect [cwd]
  ;; What a session's directory is in git: {:repo :branch :path :worktree? :base
  ;; :landing}, or nil outside a repository. For a thread's worktree, repo is the
  ;; checkout it lands in, base the branch it was made from and landing how it lands,
  ;; both from the repo's config.
  (when (and cwd (not= cwd "") (= 1 (vim.fn.isdirectory cwd)))
    (let [repo (repo-of cwd)]
      (when repo
        (let [path (or (toplevel cwd) cwd)
              branch (branch-of path)
              wt? (worktree? path)]
          {: repo : branch : path :worktree? wt?
           :base (when (and wt? branch) (or (config-get repo branch "acp-base") (default-base repo)))
           :landing (when (and wt? branch) (or (config-get repo branch "acp-landing") (landing-default)))})))))

(fn add-worktree [from landing]
  ;; A new worktree and branch for a thread started from the directory from: its
  ;; branch when it is a thread's worktree itself, else the repo's default, is the base.
  ;; Returns what inspect would, or nil and why not.
  (let [repo (repo-of from)]
    (if (not repo)
      (values nil (.. from " is not in a git repository"))
      (let [here (inspect from)
            base (if (and here.worktree? here.branch) here.branch (default-base repo))
            dir (worktree-dir repo)
            _ (vim.fn.mkdir dir "p")
            id (short-id dir)
            path (vim.fs.joinpath dir id)
            branch (.. (branch-prefix repo) "/" id)
            landing (or landing (landing-default))]
        ;; Under the project, the worktrees would otherwise show as untracked.
        (when (and (vim.startswith dir (.. repo "/"))
                   (= 0 (vim.fn.filereadable (vim.fs.joinpath dir ".gitignore"))))
          (vim.fn.writefile ["*"] (vim.fs.joinpath dir ".gitignore")))
        (let [(ok _ err) (run repo ["worktree" "add" "-b" branch path base])]
          (if (not ok)
            (values nil (.. "git worktree add failed: " err))
            (do
              (config-set repo branch "acp-base" base)
              (config-set repo branch "acp-landing" landing)
              (copy-includes repo path)
              {: repo : branch : path :worktree? true : base : landing})))))))

(fn set-landing [git landing]
  (set git.landing landing)
  (when (and git.worktree? git.branch)
    (config-set git.repo git.branch "acp-landing" landing)))

(fn rename-branch [git name]
  ;; A branch of your own naming, until it's pushed: then the remote knows the old one.
  (let [(ok out) (run git.repo ["for-each-ref" (.. "refs/remotes/*/" git.branch)])]
    (if (and ok (not= out ""))
      (values false (.. git.branch " has been pushed, so it keeps its name"))
      (let [(ok _ err) (run git.repo ["branch" "-m" git.branch name])]
        (if ok
          (do (set git.branch name) true)
          (values false err))))))

(fn unmerged [git]
  ;; What a thread's worktree holds that its base doesn't: {:ahead N :dirty?}.
  (let [(ok count) (run git.repo ["rev-list" "--count" (.. (or git.base "HEAD") ".." git.branch)])
        (ok2 status) (run git.path ["status" "--porcelain"])]
    {:ahead (if ok (or (tonumber count) 0) 0)
     :dirty? (or (not ok2) (not= status ""))}))

(fn remove-worktree [git]
  ;; The directory goes, the branch stays (deleted only once it's merged).
  (let [(ok _ err) (run git.repo ["worktree" "remove" "--force" "--force" git.path])]
    (if ok
      (do (run git.repo ["branch" "-d" git.branch]) true)
      (values false err))))

(fn worktrees [repo]
  ;; The thread worktrees of repo, as inspect gives them.
  (let [dir (worktree-dir repo)
        (ok out) (run repo ["worktree" "list" "--porcelain"])]
    (if (not ok) []
        (icollect [_ block (ipairs (vim.split out "\n\n" {:plain true :trimempty true}))]
          (let [path (string.match block "worktree (%S+)")]
            (when (and path (vim.startswith (vim.fs.normalize path) (.. dir "/")))
              (inspect path)))))))

(fn free-clean [repo busy]
  ;; Removes every thread worktree of repo with nothing uncommitted, except those busy
  ;; (paths with a session running). Returns the freed ones' branches, and the kept ones'.
  (let [freed []
        kept []]
    (each [_ git (ipairs (worktrees repo))]
      (if (or (. busy git.path) (. (unmerged git) :dirty?))
        (table.insert kept git.branch)
        (if (remove-worktree git)
          (table.insert freed git.branch)
          (table.insert kept git.branch))))
    (values freed kept)))

(fn landing-instruction [git]
  ;; How the agent is told to finish, as the first prompt's preface.
  (let [branch git.branch
        repo git.repo
        base (or git.base "the default branch")]
    (.. "[Neovim: you are working in a git worktree on branch `" branch "`, made from `" base
        "`; code changes belong on this branch. "
        (case git.landing
          "main" (.. "When a fix is ready, commit it on `" branch "`. If `" base
                     "` has moved on, merge it into `" branch
                     "` and check the build and tests still pass. Then land it in the main "
                     "checkout at `" repo "`, never in your own worktree: `git -C " repo
                     " merge --ff-only " branch "`, and confirm `git -C " repo
                     " status` is clean. Don't push or open a PR/MR.")
          "none" (.. "Commit your work on this branch, but don't push, merge or open a PR/MR: "
                     "the user decides whether and how it lands. To land it some other way "
                     "they change the thread's landing with :AcpLand.")
          _ (.. "When a fix is ready, commit, push and open a PR/MR with the forge CLI (gh or "
                "glab) and include its link. Don't merge it into the main branch yourself. "
                "If asked to land it some other way, ask for the thread's landing to be changed "
                "with :AcpLand instead: that is what gives you access to do it."))
        "]\n\n")))

(fn landing-changed [git]
  (.. "[Neovim: the thread's landing is now " git.landing ". "
      (case git.landing
        "main" (.. "When a fix is ready, land it with `git -C " git.repo " merge --ff-only "
                   git.branch "`, and don't push or open a PR/MR.")
        "none" "Commit on this branch, but don't push, merge or open a PR/MR."
        _ "When a fix is ready, commit, push and open a PR/MR with the forge CLI.")
      "]\n\n"))

;; Status for the sidebar ------------------------------------------------------------
;; Asked of git in the background and kept a while, as the sidebar redraws every second.

(local statuses {})

(fn status-seconds []
  ;; vim.g.acp-git-seconds: how long a worktree's state is kept before git is asked again.
  (or vim.g.acp-git-seconds 10))

(fn status [cwd]
  ;; {:branch :ahead :dirty? :worktree?} for the directory, or nil until git has
  ;; answered the first time.
  (when (and cwd (not= cwd ""))
    (let [now (os.time)
          entry (or (. statuses cwd) (let [e {}] (tset statuses cwd e) e))]
      (when (and (not entry.asking) (> (- now (or entry.at 0)) (status-seconds)))
        (set entry.asking true)
        (if (not (worktree? cwd))
          (do (set entry.asking false) (set entry.at now) (set entry.status {:worktree? false}))
          (pcall vim.system ["git" "-C" cwd "status" "--porcelain" "--branch"] {:text true}
                 (vim.schedule_wrap
                   (fn [result]
                     (set entry.asking false)
                     (set entry.at (os.time))
                     (when (= result.code 0)
                       (let [lines (vim.split (or result.stdout "") "\n" {:plain true :trimempty true})
                             head (or (. lines 1) "")
                             branch (string.match head "^## ([^%.%s]+)")]
                         (set entry.status {:worktree? true : branch :dirty? (> (length lines) 1)})
                         ;; How far ahead of the base, which status --branch only knows
                         ;; against an upstream.
                         (let [git (inspect cwd)]
                           (when (and git git.branch)
                             (pcall vim.system ["git" "-C" cwd "rev-list" "--count"
                                                (.. (or git.base "HEAD") ".." git.branch)]
                                    {:text true}
                                    (vim.schedule_wrap
                                      (fn [r]
                                        (when (and (= r.code 0) entry.status)
                                          (set entry.status.ahead (tonumber (vim.trim (or r.stdout "")))))))))))))))))
      entry.status)))

(fn forget-status [cwd]
  (tset statuses cwd nil))

{: inspect
 : add-worktree
 : set-landing
 : rename-branch
 : unmerged
 : remove-worktree
 : worktrees
 : free-clean
 : landing-instruction
 : landing-changed
 : landing-default
 : repo-of
 : branch-of
 : worktree?
 : worktree-dir
 : default-base
 : status
 : forget-status}
