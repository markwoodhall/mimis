;; CI status for a thread's branch and the project's default branch, from the forge's
;; CLI: gh for GitHub, glab for GitLab, chosen by origin's host. They run here with
;; your login, never in the agent's sandbox, and are asked again every two minutes
;; (vim.g.acp-ci-seconds), or ten when the CLI is missing, logged out or offline.
;;
;; A branch's status is its PR/MR and the checks on it: ✓ passed, ✗ failed, ◔ running,
;; shown beside the thread in :AcpThreads and in the chat's input header; the
;; default branch's latest build the same way on the project's heading. :AcpCi, or c in
;; the sidebar, follows the run in a terminal (gh pr checks --watch, or the failed
;; run's log) and hands its output to the agent, as :AcpRun does.

(local git (require :modules.acp.git))

(local statuses {})
(local backoff 600)

(fn seconds []
  (or vim.g.acp-ci-seconds 120))

(fn forge [repo]
  ;; :gh, :glab, or nil for a repo with no origin on either; remembered per repo.
  (let [entry (or (. statuses repo) (let [e {}] (tset statuses repo e) e))]
    (when (= entry.forge nil)
      (let [(ok result) (pcall #(: (vim.system ["git" "-C" repo "remote" "get-url" "origin"] {:text true}) :wait))
            url (if ok (vim.trim (or result.stdout "")) "")
            host (or (string.match url "@([^:/]+)[:/]") (string.match url "://([^/]+)/") "")
            kind (if (host:find "github") :gh
                     (host:find "gitlab") :glab
                     false)]
        (set entry.forge (if (and kind (not= "" (vim.fn.exepath (tostring kind)))) kind false))))
    (when entry.forge entry.forge)))

;; Parsing ----------------------------------------------------------------------------

(fn github-state [status conclusion]
  ;; A check run's status and conclusion, or a commit status's state, as one of
  ;; :passed :failed :running :none.
  (let [status (string.upper (or status ""))
        conclusion (string.upper (or conclusion ""))]
    (if (or (= status "IN_PROGRESS") (= status "QUEUED") (= status "PENDING")
            (= status "WAITING") (= status "REQUESTED") (= conclusion "PENDING"))
      :running
      (or (= conclusion "SUCCESS") (= conclusion "NEUTRAL") (= conclusion "SKIPPED"))
      :passed
      (or (= conclusion "FAILURE") (= conclusion "ERROR") (= conclusion "TIMED_OUT")
          (= conclusion "CANCELLED") (= conclusion "ACTION_REQUIRED") (= conclusion "STARTUP_FAILURE"))
      :failed
      (= status "COMPLETED")
      :passed
      :none)))

(fn worst [states]
  ;; Failed beats running beats passed; none when there are no checks.
  (accumulate [so-far :none _ st (ipairs states)]
    (if (or (= st :failed) (= so-far :failed)) :failed
        (or (= st :running) (= so-far :running)) :running
        (= st :passed) :passed
        so-far)))

(fn parse-gh-pr [json]
  ;; gh pr list --head B --state all --limit 1 --json number,url,state,statusCheckRollup
  ;; -> {:number :url :open? :state :run-id} or nil without a PR.
  (let [(ok prs) (pcall vim.json.decode json)
        pr (when (and ok (= (type prs) :table)) (. prs 1))]
    (when pr
      (let [checks (if (= (type pr.statusCheckRollup) :table) pr.statusCheckRollup [])
            states (icollect [_ c (ipairs checks)]
                     (if (= c.__typename "StatusContext")
                       (github-state "" c.state)
                       (github-state c.status c.conclusion)))
            ;; The first failed or running Actions job's run, for gh run view.
            run-id (accumulate [found nil _ c (ipairs checks) &until found]
                     (let [st (if (= c.__typename "StatusContext") :none (github-state c.status c.conclusion))]
                       (when (or (= st :failed) (= st :running))
                         (string.match (or c.detailsUrl "") "/actions/runs/(%d+)"))))]
        {:number pr.number
         :url pr.url
         :open? (= "OPEN" (string.upper (or pr.state "")))
         :state (worst states)
         :run-id run-id}))))

(fn parse-gh-runs [json]
  ;; gh run list --branch B --limit 1 --json status,conclusion,url,name,databaseId
  ;; -> {:state :url :name :run-id} or nil without a run.
  (let [(ok runs) (pcall vim.json.decode json)
        run (when (and ok (= (type runs) :table)) (. runs 1))]
    (when run
      {:state (github-state run.status run.conclusion)
       :url run.url
       :name run.name
       :run-id (when run.databaseId (tostring run.databaseId))})))

(fn gitlab-state [status]
  (case (string.lower (or status ""))
    "success" :passed
    "failed" :failed
    "canceled" :failed
    "running" :running
    "pending" :running
    "created" :running
    "waiting_for_resource" :running
    "preparing" :running
    "scheduled" :running
    "manual" :running
    "skipped" :passed
    _ :none))

(fn parse-glab-mr [json]
  ;; glab mr list --source-branch B --all -F json -> {:number :url :open?}: the open one,
  ;; else the newest.
  (let [(ok mrs) (pcall vim.json.decode json)
        mrs (if (and ok (= (type mrs) :table)) mrs [])
        open (accumulate [found nil _ mr (ipairs mrs) &until found]
               (when (= mr.state "opened") mr))
        mr (or open (. mrs 1))]
    (when mr
      {:number mr.iid :url mr.web_url :open? (= mr.state "opened")})))

(fn parse-glab-pipeline [json]
  ;; glab ci list --ref B -F json (or ci get -F json) -> {:state :url} of the newest.
  (let [(ok data) (pcall vim.json.decode json)
        p (when (and ok (= (type data) :table)) (if (. data 1) (. data 1) data))]
    (when (and p p.status)
      {:state (gitlab-state p.status) :url p.web_url})))

;; Asking ------------------------------------------------------------------------------

(fn run [argv cwd done]
  (pcall vim.system argv {:text true :cwd cwd}
         (vim.schedule_wrap
           (fn [result]
             (done (= result.code 0) (or result.stdout "") (or result.stderr ""))))))

(fn entry-for [key]
  (or (. statuses key) (let [e {}] (tset statuses key e) e)))

(fn stale? [entry now]
  (and (not entry.asking)
       (> (- now (or entry.at 0)) (if entry.failed backoff (seconds)))))

(fn settle [entry status ok?]
  (set entry.asking false)
  (set entry.at (os.time))
  (set entry.failed (not ok?))
  (when ok? (set entry.status status)))

(fn branch-status [repo branch]
  ;; The PR/MR on branch and its checks, from the last answer; asks again when it's
  ;; stale. nil until the forge has answered, or when there is none.
  (let [kind (forge repo)]
    (when (and kind branch)
      (let [entry (entry-for (.. repo "#" branch))
            now (os.time)]
        (when (stale? entry now)
          (set entry.asking true)
          (if (= kind :gh)
            (run ["gh" "pr" "list" "--head" branch "--state" "all" "--limit" "1"
                  "--json" "number,url,state,statusCheckRollup"]
                 repo
                 (fn [ok out]
                   (settle entry (when ok (parse-gh-pr out)) ok)))
            (run ["glab" "mr" "list" "--source-branch" branch "--all" "-F" "json"] repo
                 (fn [ok out]
                   (if (not ok)
                     (settle entry nil false)
                     (let [mr (parse-glab-mr out)]
                       (run ["glab" "ci" "get" "--branch" branch "-F" "json"] repo
                            (fn [ok2 out2]
                              (let [pipeline (when ok2 (parse-glab-pipeline out2))]
                                (settle entry
                                        (when (or mr pipeline)
                                          (vim.tbl_extend :force (or mr {})
                                                          {:state (or (?. pipeline :state) :none)
                                                           :kind :glab}))
                                        true))))))))))
        entry.status))))

(fn default-branch [repo]
  (let [entry (entry-for repo)]
    (when (not entry.default)
      (set entry.default (git.default-base repo)))
    entry.default))

(fn build-status [repo]
  ;; The latest build of the repo's default branch, the same way.
  (let [kind (forge repo)]
    (when kind
      (let [entry (entry-for (.. repo "#"))
            now (os.time)
            default (default-branch repo)]
        (when (stale? entry now)
          (set entry.asking true)
          (if (= kind :gh)
            (run ["gh" "run" "list" "--branch" default "--limit" "1"
                  "--json" "status,conclusion,url,name,databaseId"]
                 repo
                 (fn [ok out]
                   (settle entry (when ok (parse-gh-runs out)) ok)))
            (run ["glab" "ci" "list" "--ref" default "-F" "json"] repo
                 (fn [ok out]
                   (settle entry (when ok (parse-glab-pipeline out)) ok)))))
        entry.status))))

(fn glyph [state]
  (case state
    :passed "✓"
    :failed "✗"
    :running "◔"
    _ nil))

(fn group [state]
  (case state
    :passed :AcpCiPassed
    :failed :AcpCiFailed
    :running :AcpCiRunning
    _ :AcpThreadsMeta))

(fn word [state]
  (case state
    :passed "passed"
    :failed "failed"
    :running "running"
    _ "no checks"))

(fn summary [status]
  ;; "PR #42 · failed", for the chat's header and messages. nil without a PR/MR.
  (when (and status status.number)
    (.. (if (= :glab status.kind) "MR" "PR") " #" status.number " · " (word status.state))))

(fn follow-command [repo branch status]
  ;; A shell command to watch or read the checks of branch: the failed run's log, the
  ;; running checks until they finish, else the checks as they stand. nil without a forge.
  (let [kind (forge repo)]
    (when kind
      (if (= kind :gh)
        (if (and status (= status.state :failed) status.run-id)
          (.. "gh run view " status.run-id " --log-failed")
          (and status status.number (= status.state :running))
          (.. "gh pr checks " status.number " --watch")
          (and status status.number)
          (.. "gh pr checks " status.number)
          (.. "gh run list --branch " (vim.fn.shellescape branch) " --limit 5"))
        (.. "glab ci trace --branch " (vim.fn.shellescape branch))))))

(fn highlights []
  (vim.api.nvim_set_hl 0 :AcpCiPassed {:link :DiagnosticOk :default true})
  (vim.api.nvim_set_hl 0 :AcpCiFailed {:link :DiagnosticError :default true})
  (vim.api.nvim_set_hl 0 :AcpCiRunning {:link :DiagnosticWarn :default true}))

(fn forget []
  (each [k (pairs statuses)]
    (tset statuses k nil)))

{: forge
 : branch-status
 : build-status
 : parse-gh-pr
 : parse-gh-runs
 : parse-glab-mr
 : parse-glab-pipeline
 : glyph
 : group
 : word
 : summary
 : follow-command
 : highlights
 : forget}
