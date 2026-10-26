;; Account spend and credits. ACP has no message for these, so they come from a command
;; of the agent's profile (:credits-cmd), run outside the agent. "{cwd}" in an argument
;; becomes the session's directory.
;;
;; The command must exit 0. JSON output is read as either opencode stats --json (the
;; spend over its range) or OpenCode's usage limits (GET /api/experimental/usage/limits,
;; documented but not in a release yet: Go allowance and Console budgets). Anything else
;; shows as its first line, so a script of your own can print whatever it likes.
;; vim.g.acp-credits = false turns it all off.

(local transport (require :modules.acp.transport))

(local max-width 40)

(fn enabled? []
  (not= vim.g.acp-credits false))

(fn money [amount]
  (string.format "$%.2f" amount))

(fn go-summary [go]
  ;; The fullest of the Go allowance's windows.
  (when (= (type go) :table)
    (var top nil)
    (var limited false)
    (each [_ window (ipairs [:rolling :weekly :monthly])]
      (let [meter (. go window)]
        (when (= (type meter) :table)
          (when meter.limited (set limited true))
          (when (and (= (type meter.percent) :number) (or (not top) (> meter.percent top)))
            (set top meter.percent)))))
    (if limited "go limited"
        top (.. "go " (math.floor (+ top 0.5)) "%"))))

(fn budget-summary [budgets]
  ;; Spent and limit of the budgets that apply to the current choice, else of all.
  (let [budgets (if (= (type budgets) :table) budgets [])
        picked (vim.tbl_filter #$1.picked budgets)
        shown (if (> (length picked) 0) picked budgets)
        parts (icollect [_ b (ipairs shown)]
                (when (and (= (type b.spent) :number) (= (type b.limit) :number))
                  (.. (money b.spent) "/" (money b.limit))))]
    (when (> (length parts) 0)
      (table.concat parts " "))))

(fn usage-limits-summary [decoded]
  ;; nil when not signed in, or when there's nothing to show.
  (let [info (?. decoded :data)]
    (when (= (type info) :table)
      (let [parts (icollect [_ part (ipairs [(go-summary info.go) (budget-summary info.budgets)])]
                    part)]
        (when (> (length parts) 0)
          (table.concat parts " · "))))))

(local day-ms (* 24 60 60 1000))

(fn stats-summary [decoded]
  ;; opencode stats --json: what was spent over its range, e.g. "30d $69.25". The range
  ;; runs from midnight some days back to now, so part of a day counts as one.
  (let [from (?. decoded :range :from)
        to (?. decoded :range :to)
        days (when (and (= (type from) :number) (= (type to) :number) (> to from))
               (math.ceil (/ (- to from) day-ms)))
        label (if days (.. days "d") "spent")]
    (.. label " " (money decoded.cost))))

(fn summary [output]
  ;; Command output -> statusline text, or nil.
  (let [text (vim.trim (or output ""))
        (ok decoded) (pcall vim.json.decode text {:luanil {:object true :array true}})]
    (if (= text "") nil
        (and ok (= (type decoded) :table) (= (type decoded.cost) :number)) (stats-summary decoded)
        (and ok (= (type decoded) :table)) (usage-limits-summary decoded)
        (let [line (vim.trim (. (vim.split text "\n" {:plain true}) 1))]
          (if (> (vim.fn.strchars line) max-width)
            (.. (vim.fn.strcharpart line 0 (- max-width 1)) "…")
            line)))))

(fn expand [cmd cwd]
  (let [replacement (pick-values 1 (string.gsub cwd "%%" "%%%%"))]
    (icollect [_ arg (ipairs cmd)]
      (pick-values 1 (string.gsub arg "{cwd}" replacement)))))

(fn fetch [cmd cwd done]
  ;; Runs cmd and calls done with the summary, or nil if it failed or said nothing.
  ;; Failures go to the debug log, as the statusline just keeps the last figure.
  (let [argv (expand cmd cwd)
        (ok err) (pcall vim.system argv {: cwd :text true :timeout 15000}
                        (fn [obj]
                          (vim.schedule
                            (fn []
                              (when (not= obj.code 0)
                                (transport.debug "!!" (.. "credits: " (table.concat argv " ")
                                                          " exited " obj.code ": "
                                                          (vim.trim (.. (or obj.stdout "") " "
                                                                        (or obj.stderr ""))))))
                              (done (when (= obj.code 0) (summary obj.stdout)))))))]
    (when (not ok)
      (vim.schedule (fn []
                      (transport.debug "!!" (.. "credits: could not run " (table.concat argv " ")
                                                ": " (tostring err)))
                      (done nil err))))))

{: enabled?
 : summary
 : fetch}
