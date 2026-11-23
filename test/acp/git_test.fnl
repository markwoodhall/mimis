;; End-to-end tests for worktree threads, landing and CI status (modules.acp.git and
;; modules.acp.ci), with test/acp/fake_agent.py as the agent, a git repository made
;; here, and a fake gh on the path.
;; Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/git_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(set vim.g.acp-agent-cmd ["python3" (.. here "/fake_agent.py")])
(set vim.g.acp-agents {})
(set vim.g.acp-credits false)
(set vim.g.acp-log-dir (vim.fn.tempname))
(set vim.g.acp-debug-log (vim.fn.tempname))
(set vim.g.acp-config-cache (vim.fn.tempname))
(set vim.g.acp-egress-log-dir (vim.fn.tempname))
(set vim.g.acp-notify false)
;; Asked often, so the tests needn't wait.
(set vim.g.acp-ci-seconds 1)
(set vim.g.acp-git-seconds 1)

(local session (require :modules.acp.session))
(local render (require :modules.acp.render))
(local git (require :modules.acp.git))
(local ci (require :modules.acp.ci))
(local history (require :modules.acp.history))
(local sandbox (require :modules.acp.sandbox))
(local acp (require :modules.acp))
(local failures [])

(fn out [line]
  (io.stdout:write (.. line "\n")))

(fn check [name ok detail]
  (if ok
    (out (.. "ok   " name))
    (do
      (table.insert failures name)
      (out (.. "FAIL " name (if (not= detail nil) (.. "\n     " (vim.inspect detail)) ""))))))

(fn wait [pred ms]
  (vim.wait (or ms 5000) pred 10))

(fn lines-of [buf]
  (vim.api.nvim_buf_get_lines buf 0 -1 false))

(fn has-line [lines text]
  (accumulate [found false _ l (ipairs lines)]
    (or found (not= nil (string.find l text 1 true)))))

;; Permission requests are answered with :AcpAllow, as the fake agent asks one on
;; every ordinary prompt.
(local auto-timer (vim.uv.new_timer))
(auto-timer:start 20 20 (vim.schedule_wrap
                          (fn []
                            (let [current (session.current)]
                              (when (and current current.permission)
                                (vim.cmd "AcpAllow"))))))

(fn sh [cwd args]
  (let [r (: (vim.system args {:text true : cwd}) :wait)]
    (values (= r.code 0) (vim.trim (or r.stdout "")) (vim.trim (or r.stderr "")))))

(fn git-in [cwd ...]
  (sh cwd (vim.list_extend ["git" "-c" "user.name=t" "-c" "user.email=t@t" "-c" "commit.gpgsign=false"] [...])))

(fn git-out [cwd ...]
  ;; Just what git printed.
  (let [(_ out) (git-in cwd ...)] out))

;; A fake gh: a PR with one check still running, and a passing build on main.
(local bin (vim.fn.tempname))
(vim.fn.mkdir bin "p")
(vim.fn.writefile
  ["#!/bin/sh"
   "echo \"$*\" >> \"$0.calls\""
   "case \"$*\" in"
   "  *'pr list'*) echo '[{\"number\":42,\"state\":\"OPEN\",\"url\":\"https://github.com/m/u/pull/42\",\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"name\":\"test\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"},{\"__typename\":\"CheckRun\",\"name\":\"lint\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",\"detailsUrl\":\"https://github.com/m/u/actions/runs/222/job/2\"}]}]' ;;"
   "  *'run list'*) echo '[{\"conclusion\":\"success\",\"name\":\"ci\",\"status\":\"completed\",\"url\":\"u\",\"databaseId\":9}]' ;;"
   "  *) echo \"gh $*\" ;;"
   "esac"]
  (.. bin "/gh"))
(vim.fn.setfperm (.. bin "/gh") "rwxr-xr-x")
(set vim.env.PATH (.. bin ":" vim.env.PATH))

;; The repository: a commit on main, an untracked .mcp.json to copy in, and a GitHub origin.
(local repo (.. (vim.fn.tempname) "/proj"))
(vim.fn.mkdir repo "p")
(git-in repo "init" "-q" "-b" "main")
(vim.fn.writefile ["hello"] (.. repo "/README.md"))
(git-in repo "add" "README.md")
(git-in repo "commit" "-q" "-m" "first")
(vim.fn.writefile ["{\"servers\":{}}"] (.. repo "/.mcp.json"))
(vim.fn.writefile [".mcp.json"] (.. repo "/.gitignore"))
(git-in repo "add" ".gitignore")
(git-in repo "commit" "-q" "-m" "ignore")
(git-in repo "remote" "add" "origin" "git@github.com:m/proj.git")
(vim.cmd (.. "cd " (vim.fn.fnameescape repo)))

;; Parsing the arguments -----------------------------------------------------------

(check "worktree and land= are picked out of :Acp's arguments"
       (vim.deep_equal {:worktree true :landing "main" :settings {:model "x"}}
                       (acp.parse-args ["worktree" "land=main" "model" "x"]))
       (acp.parse-args ["worktree" "land=main" "model" "x"]))
(check "wt is short for worktree"
       (vim.deep_equal {:worktree true :settings {}} (acp.parse-args ["wt"])))
(check "a landing on its own means a worktree"
       (vim.deep_equal {:worktree true :landing "none" :settings {}} (acp.parse-args ["land=none"])))
(let [(parsed problem) (acp.parse-args ["land=sideways"])]
  (check "an unknown landing is refused" (and (= nil parsed) (string.find problem "pr, main or none" 1 true))
         problem))

;; Parsing the forge's answers ---------------------------------------------------------

(let [pr (ci.parse-gh-pr "[{\"number\":42,\"state\":\"OPEN\",\"url\":\"u\",\"statusCheckRollup\":[
           {\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"},
           {\"__typename\":\"CheckRun\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\",\"detailsUrl\":\"https://github.com/m/u/actions/runs/222/job/2\"},
           {\"__typename\":\"StatusContext\",\"context\":\"ci/legacy\",\"state\":\"SUCCESS\"}]}]")]
  (check "a PR with a check running is running, and names the run"
         (and (= 42 pr.number) pr.open? (= :running pr.state) (= "222" pr.run-id)) pr))
(check "a failed check makes the PR failed"
       (= :failed (. (ci.parse-gh-pr "[{\"number\":1,\"url\":\"u\",\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"},{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}]") :state)))
(check "skipped and neutral checks pass"
       (= :passed (. (ci.parse-gh-pr "[{\"number\":1,\"url\":\"u\",\"statusCheckRollup\":[{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"SKIPPED\"},{\"__typename\":\"StatusContext\",\"state\":\"SUCCESS\"}]}]") :state)))
(check "a pending commit status is running"
       (= :running (. (ci.parse-gh-pr "[{\"number\":1,\"url\":\"u\",\"statusCheckRollup\":[{\"__typename\":\"StatusContext\",\"state\":\"PENDING\"}]}]") :state)))
(check "a PR with no checks has none"
       (= :none (. (ci.parse-gh-pr "[{\"number\":7,\"url\":\"u\",\"state\":\"OPEN\",\"statusCheckRollup\":[]}]") :state)))
(check "no PR is nil" (= nil (ci.parse-gh-pr "[]")))
(check "a run list gives the latest run's state"
       (vim.deep_equal {:state :failed :url "u" :name "deploy" :run-id "9"}
                       (ci.parse-gh-runs "[{\"conclusion\":\"failure\",\"name\":\"deploy\",\"status\":\"completed\",\"url\":\"u\",\"databaseId\":9}]")))
(check "a queued run is running"
       (= :running (. (ci.parse-gh-runs "[{\"conclusion\":\"\",\"name\":\"ci\",\"status\":\"queued\",\"url\":\"u\"}]") :state)))
(check "the open MR wins over a closed one"
       (vim.deep_equal {:number 42 :url "https://gitlab.com/j/a/-/merge_requests/42" :open? true}
                       (ci.parse-glab-mr "[{\"iid\":41,\"state\":\"closed\",\"web_url\":\"c\"},{\"iid\":42,\"state\":\"opened\",\"web_url\":\"https://gitlab.com/j/a/-/merge_requests/42\"}]")))
(check "a GitLab pipeline's status is read"
       (= :failed (. (ci.parse-glab-pipeline "[{\"status\":\"failed\",\"web_url\":\"p\"}]") :state)))
(check "the follow command reads a failed run's log"
       (= "gh run view 222 --log-failed" (ci.follow-command repo "x" {:state :failed :run-id "222" :number 1})))
(check "the follow command watches running checks"
       (= "gh pr checks 42 --watch" (ci.follow-command repo "x" {:state :running :number 42})))
(check "the follow command lists runs without a PR"
       (= "gh run list --branch 'x' --limit 5" (ci.follow-command repo "x" nil)))
(check "the summary names the PR and its state" (= "PR #42 · running" (ci.summary {:number 42 :state :running})))
(check "origin on GitHub means gh" (= :gh (ci.forge repo)))

;; A thread in a worktree of its own -------------------------------------------------

(vim.cmd "Acp worktree land=main")
(local s (session.current))
(check "the session is in a worktree under the project"
       (vim.startswith s.session.cwd (.. repo "/.acp/worktrees/")) s.session.cwd)
(check "the session knows its worktree"
       (and s.git s.git.worktree? (= repo s.git.repo) (= "main" s.git.base) (= "main" s.git.landing)
            (vim.startswith s.git.branch "proj/"))
       s.git)
(local wt s.git.path)
(local branch s.git.branch)
(check "git lists the worktree on its branch"
       (let [(ok out) (git-in repo "worktree" "list" "--porcelain")]
         (and ok (string.find out wt 1 true) (string.find out (.. "refs/heads/" branch) 1 true)))
       (git-in repo "worktree" "list" "--porcelain"))
(check "the worktree is a checkout of the base" (= 1 (vim.fn.filereadable (.. wt "/README.md"))))
(check "the untracked .mcp.json is copied in" (= 1 (vim.fn.filereadable (.. wt "/.mcp.json"))))
(check "the base and landing are kept in the repo's config"
       (let [(_ base) (git-in repo "config" (.. "branch." branch ".acp-base"))
             (_ landing) (git-in repo "config" (.. "branch." branch ".acp-landing"))]
         (and (= "main" base) (= "main" landing))))
(check "the main checkout stays clean"
       (= "" (git-out repo "status" "--porcelain")) (git-out repo "status" "--porcelain"))
(check "the worktrees directory ignores itself"
       (= 1 (vim.fn.filereadable (.. repo "/.acp/worktrees/.gitignore"))))
(check "inspecting the worktree gives the same"
       (let [info (git.inspect wt)]
         (and info info.worktree? (= branch info.branch) (= repo info.repo) (= "main" info.landing)))
       (git.inspect wt))

(wait #(and (not= nil s.session.id) s.ready))
(check "the chat says where it is and how it lands"
       (has-line (lines-of s.buf) (.. "> acp: worktree on " branch " from main · lands as main · main checkout " repo))
       (lines-of s.buf))

;; The agent is told how to land before its first prompt, and only then.
(vim.cmd "AcpSend hello")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "the first prompt carries the landing instruction"
         (and (has-line chat "you are working in a git worktree on branch")
              (has-line chat (.. "`git -C " repo " merge --ff-only " branch "`")))
         chat)
  (check "the chat notes the agent was told" (has-line chat "> acp: told the agent about its worktree: lands as main")))
(vim.cmd "AcpSend plain")
(wait #(= s.turn.state :idle))
(check "later prompts go as they are" (has-line (lines-of s.buf) "Plain reply."))

;; The log and the sidebar's reading of it.
(let [path s.log.path
      read (history.read path)]
  (check "the log records the branch and landing"
         (and (= branch read.branch) (= "main" read.landing) (= repo read.repo)) read))

;; The input header shows the landing and the PR's checks, from the fake gh.
(wait #(not= nil (ci.branch-status repo branch)) 5000)
(let [pr (ci.branch-status repo branch)]
  (check "the branch's PR and checks come from gh" (and pr (= 42 pr.number) (= :running pr.state)) pr))
(check "gh ran with the repo's branch"
       (has-line (vim.fn.readfile (.. bin "/gh.calls")) (.. "pr list --head " branch)))
(let [footer (render.input-footer s)
      text (table.concat (icollect [_ [t] (ipairs footer)] t) "")]
  (check "the input header shows the landing and the checks"
         (and (string.find text "lands as main" 1 true) (string.find text "◔ PR #42 · running" 1 true))
         text))

;; Changing the landing.
(vim.cmd "AcpLand pr")
(wait #(has-line (lines-of s.buf) "> acp: lands as pr"))
(check "AcpLand changes the landing" (= "pr" s.git.landing))
(check "and keeps it in the repo's config"
       (= "pr" (git-out repo "config" (.. "branch." branch ".acp-landing"))))
(vim.cmd "AcpSend hello again")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "the next prompt tells the agent" (has-line chat "the thread's landing is now pr"))
  (check "and the chat notes it" (has-line chat "> acp: told the agent about its worktree: now lands as pr")))
(vim.cmd "AcpLand sideways")
(check "an unknown landing is refused and nothing changes" (= "pr" s.git.landing))

;; The sandbox's binds for a worktree.
(let [argv (sandbox.worktree-binds {} wt)
      text (table.concat argv " ")]
  (check "the worktree's repository .git is bound writable"
         (string.find text (.. "--bind " repo "/.git " repo "/.git") 1 true) text)
  (check "with its hooks, config, HEAD and index frozen"
         (and (string.find text (.. "--ro-bind " repo "/.git/hooks") 1 true)
              (string.find text (.. "--ro-bind " repo "/.git/config") 1 true)
              (string.find text (.. "--ro-bind " repo "/.git/HEAD") 1 true)
              (string.find text (.. "--ro-bind " repo "/.git/index") 1 true))
         text))
(let [argv (sandbox.worktree-binds {:repo-write repo} wt)
      text (table.concat argv " ")]
  (check "landing on main binds the main checkout writable"
         (string.find text (.. "--bind " repo " " repo) 1 true) text)
  (check "with hooks and config frozen but HEAD free"
         (and (string.find text (.. "--ro-bind " repo "/.git/hooks") 1 true)
              (not (string.find text "/.git/HEAD" 1 true)))
         text))
(check "a plain checkout needs no worktree binds" (= 0 (length (sandbox.worktree-binds {} repo))))
(check "the sandbox spec keeps repo-write"
       (= repo (. (sandbox.normalize {:net :proxy :repo-write repo}) :repo-write)))

;; Work in the worktree shows in the sidebar.
(vim.fn.writefile ["more"] (.. wt "/more.txt"))
(git-in wt "add" "more.txt")
(git-in wt "commit" "-q" "-m" "more")
(vim.fn.writefile ["dirty"] (.. wt "/dirty.txt"))
(wait #(let [st (git.status wt)] (and st (= 1 st.ahead) st.dirty?)) 5000)
(let [st (git.status wt)]
  (check "the worktree's state is a commit ahead and dirty" (and st (= 1 st.ahead) st.dirty?) st))
(check "unmerged counts the same" (vim.deep_equal {:ahead 1 :dirty? true} (git.unmerged s.git)))

(vim.cmd "AcpThreads")
(local threads-buf (vim.api.nvim_get_current_buf))
(wait #(let [lines (lines-of threads-buf)]
         (and (accumulate [found false _ l (ipairs lines)]
                (or found (and (string.find l "↑1" 1 true) (string.find l "~" 1 true) (string.find l "◔" 1 true))))
              (accumulate [found false _ l (ipairs lines)]
                (or found (and (string.find l "proj" 1 true) (string.find l "✓" 1 true)))))) 5000)
(check "the worktree thread is listed under its project, not its id"
       (= "proj" s.session.project) s.session.project)
(let [lines (lines-of threads-buf)]
  (check "the thread's row shows its commits, changes and checks"
         (accumulate [found false _ l (ipairs lines)]
           (or found (and (string.find l "↑1" 1 true) (string.find l "~ ◔" 1 true))))
         lines)
  (check "the project's heading shows main's build"
         (accumulate [found false _ l (ipairs lines)]
           (or found (and (string.find l "proj" 1 true) (string.find l "✓" 1 true))))
         lines))
(vim.cmd "AcpThreads")

;; A thread started from the chat builds on its branch.
(vim.api.nvim_set_current_buf s.buf)
(vim.cmd "Acp worktree")
(local s2 (session.current))
(check "a second worktree session starts" (and (not= s2 s) s2.git s2.git.worktree?) (?. s2 :git))
(check "forked from the chat, its base is the first thread's branch"
       (= branch s2.git.base) s2.git)
(check "and it lands as the default" (= "pr" s2.git.landing))
(check "the first session keeps running" (session.alive? s))
(wait #(and (not= nil s2.session.id) s2.ready))
(check "the forked worktree has the first's commit" (= 1 (vim.fn.filereadable (.. s2.git.path "/more.txt"))))

;; Freeing worktrees: a running one and a dirty one stay.
(let [(freed kept) (git.free-clean repo {(vim.fs.normalize s.git.path) true (vim.fs.normalize s2.git.path) true})]
  (check "running worktrees are kept" (and (= 0 (length freed)) (= 2 (length kept))) [freed kept]))
(local wt2 s2.git.path)
(local branch2 s2.git.branch)
(vim.cmd "AcpStop")
(wait #(not (session.alive? s2)))
(let [(freed kept) (git.free-clean repo {(vim.fs.normalize wt) true})]
  (check "a clean worktree with no session is freed" (vim.deep_equal [branch2] freed) [freed kept])
  (check "the dirty one is kept" (vim.deep_equal [branch] kept) kept))
(check "the freed worktree is gone" (= 0 (vim.fn.isdirectory wt2)))
(check "but its branch stays, as it isn't merged"
       (pick-values 1 (git-in repo "rev-parse" "--verify" (.. "refs/heads/" branch2))))

;; Renaming the branch.
(let [(ok err) (git.rename-branch s.git "feature/named")]
  (check "the branch can be renamed before it's pushed" (and ok (= "feature/named" s.git.branch)) err))
(check "git knows the new name" (pick-values 1 (git-in repo "rev-parse" "--verify" "refs/heads/feature/named")))
(check "the landing goes with it"
       (= "pr" (git-out repo "config" "branch.feature/named.acp-landing")))

;; :Acp! in the chat stays in the worktree.
(vim.api.nvim_set_current_buf s.buf)
(vim.cmd "Acp!")
(local s3 (session.current))
(check "Acp! starts again in the same worktree" (and (not= s3 s) (= wt s3.session.cwd)) (?. s3 :session :cwd))
(check "and knows the worktree it's in"
       (and s3.git s3.git.worktree? (= "feature/named" s3.git.branch) (= "pr" s3.git.landing)) s3.git)
(check "a fresh agent in the worktree is told how it lands too" (= :first s3.tell-landing))
(check "Acp! ended the first session" (not (session.alive? s)))
(wait #(and (not= nil s3.session.id) s3.ready))

;; Deleting a thread from the sidebar removes its worktree, once its session has ended.
(vim.api.nvim_set_current_buf s3.buf)
(vim.cmd "AcpStop")
(wait #(not (session.alive? s3)))
(set vim.ui.select (fn [items opts on-choice] (on-choice (. items 1))))
(vim.cmd "AcpThreads")
(local tb (vim.api.nvim_get_current_buf))
(let [row (accumulate [found nil i l (ipairs (lines-of tb)) &until found]
            (when (string.find l "hello" 1 true) i))]
  (check "the thread is in the sidebar" (not= nil row) (lines-of tb))
  (when row
    (vim.api.nvim_win_set_cursor 0 [row 0])
    (vim.cmd "normal d")
    (wait #(= 0 (vim.fn.isdirectory wt)) 5000)
    (check "d removes the thread's worktree" (= 0 (vim.fn.isdirectory wt)))
    (check "and its unmerged branch stays"
           (pick-values 1 (git-in repo "rev-parse" "--verify" "refs/heads/feature/named")))))
(vim.cmd "AcpThreads")

(check "the main checkout was never touched"
       (and (= "main" (git-out repo "branch" "--show-current"))
            (= "" (git-out repo "status" "--porcelain")))
       (git-out repo "status" "--porcelain"))

(vim.fn.delete vim.g.acp-log-dir "rf")
(vim.fn.delete vim.g.acp-debug-log)
(vim.fn.delete vim.g.acp-config-cache)
(vim.fn.delete (vim.fn.fnamemodify repo ":h") "rf")
(vim.fn.delete bin "rf")
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
