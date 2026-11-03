;; :AcpUsage, a buffer of the account's usage: spend, tokens, spend by model, activity,
;; tool reliability and, where the agent's service says, its limits and when they reset.
;;
;; ACP itself only reports the running session's context and cost (usage_update), which
;; shows under "This session". The rest comes from commands of the agent's profile, run
;; outside the agent (see modules.acp.agents):
;;   :usage-cmd   output shaped like opencode stats --json; anything else shows as it is,
;;                so a script of your own can print whatever it likes. An argument that
;;                is exactly "{range}" becomes --days N or --all, "{project}" becomes
;;                --project . when only this project is shown (and nothing otherwise),
;;                and "{cwd}" in an argument becomes the project's directory.
;;   :limits-cmd  OpenCode's usage limits (GET /api/experimental/usage/limits): the Go
;;                allowance's windows, Console budgets and when they reset. The endpoint
;;                is documented but not in a release yet; until it is, the command fails
;;                and the section just says so.
;;
;; In the buffer: r refreshes, < and > shorten and lengthen the range, p switches between
;; this project and every project, q closes.

(local agents (require :modules.acp.agents))
(local session (require :modules.acp.session))
(local transport (require :modules.acp.transport))

(local ns (vim.api.nvim_create_namespace "acp-usage"))
(local width 72)
(local ranges [0 7 30 90 365 :all])
(local default-range 30)
(local chart-height 5)
(local chart-columns 36)
(local tool-rows 10)

(local hl {:title "AcpUsageTitle"
           :heading "AcpUsageHeading"
           :rule "AcpUsageRule"
           :label "AcpUsageLabel"
           :value "AcpUsageValue"
           :money "AcpUsageMoney"
           :bar "AcpUsageBar"
           :track "AcpUsageTrack"
           :warn "AcpUsageWarn"
           :bad "AcpUsageBad"})

(fn highlights []
  (each [group target (pairs {hl.title :Title
                              hl.heading :Title
                              hl.rule :NonText
                              hl.label :Comment
                              hl.value :Number
                              hl.money :String
                              hl.bar :Special
                              hl.track :NonText
                              hl.warn :DiagnosticWarn
                              hl.bad :DiagnosticError})]
    (vim.api.nvim_set_hl 0 group {:link target :default true})))

;; Formatting -----------------------------------------------------------------------

(fn num? [x] (= (type x) :number))

(fn money [amount]
  (string.format "$%.2f" (or amount 0)))

(fn grouped [n]
  ;; 4687 -> "4,687"
  (let [text (tostring (math.floor (+ (or n 0) 0.5)))
        (sign digits) (string.match text "^(-?)(%d+)$")]
    (if (not digits)
      text
      (do
        (var head digits)
        (var tail "")
        (while (> (length head) 3)
          (set tail (.. "," (string.sub head -3) tail))
          (set head (string.sub head 1 -4)))
        (.. sign head tail)))))

(fn compact [n]
  ;; 9684527 -> "9.7M"
  (let [n (or n 0)]
    (if (>= n 1e9) (string.format "%.1fB" (/ n 1e9))
        (>= n 1e6) (string.format "%.1fM" (/ n 1e6))
        (>= n 1e4) (string.format "%.1fk" (/ n 1e3))
        (grouped n))))

(fn percent [fraction]
  (if (and (> fraction 0) (< fraction 0.001)) "<0.1%"
      (string.format "%.1f%%" (* 100 fraction))))

(fn duration [ms]
  ;; 954793 -> "15m55s", 6809 -> "6.8s", 15 -> "15ms"
  (if (not (num? ms)) ""
      (< ms 1000) (.. (math.floor (+ ms 0.5)) "ms")
      (< ms 60000) (string.format "%.1fs" (/ ms 1000))
      (< ms 3600000) (let [s (math.floor (/ ms 1000))]
                       (string.format "%dm%02ds" (math.floor (/ s 60)) (% s 60)))
      (let [m (math.floor (/ ms 60000))]
        (string.format "%dh%02dm" (math.floor (/ m 60)) (% m 60)))))

(fn plural [n word]
  (.. (grouped n) " " word (if (= n 1) "" "s")))

(fn pad [text w]
  (let [text (tostring text)
        gap (- w (vim.fn.strdisplaywidth text))]
    (if (> gap 0) (.. text (string.rep " " gap)) text)))

(fn lpad [text w]
  (let [text (tostring text)
        gap (- w (vim.fn.strdisplaywidth text))]
    (if (> gap 0) (.. (string.rep " " gap) text) text)))

(fn cut [text w]
  (if (> (vim.fn.strchars text) w)
    (.. (vim.fn.strcharpart text 0 (- w 1)) "…")
    text))

(local eighths ["▏" "▎" "▍" "▌" "▋" "▊" "▉"])
(local rising ["▁" "▂" "▃" "▄" "▅" "▆" "▇"])

(fn bar [fraction w]
  ;; A horizontal bar w cells wide, as [filled track]: whole blocks then an eighth for
  ;; the remainder. Anything above nothing shows at least a sliver.
  (let [fraction (math.max 0 (math.min 1 (or fraction 0)))
        units (math.floor (+ (* fraction w 8) 0.5))
        units (if (and (> fraction 0) (= units 0)) 1 units)
        full (math.floor (/ units 8))
        part (% units 8)
        filled (.. (string.rep "█" full) (if (> part 0) (. eighths part) ""))
        used (+ full (if (> part 0) 1 0))]
    [filled (string.rep "░" (- w used))]))

;; The document: lines plus the highlights on them -----------------------------------

(fn new-doc []
  {:lines [] :marks []})

(fn line [doc segments]
  ;; segments: strings, or [text group]. Columns are bytes, as extmarks want.
  (let [row (length doc.lines)
        parts []]
    (var col 0)
    (each [_ seg (ipairs segments)]
      (let [text (if (= (type seg) :table) (. seg 1) seg)
            group (when (= (type seg) :table) (. seg 2))]
        (when (and group (> (length text) 0))
          (table.insert doc.marks {: row : col :end-col (+ col (length text)) : group}))
        (table.insert parts text)
        (set col (+ col (length text)))))
    ;; Without the padding of the last column; a highlight running into it stops short.
    (let [text (string.gsub (table.concat parts) "%s+$" "")]
      (each [_ m (ipairs doc.marks)]
        (when (= m.row row)
          (set m.end-col (math.min m.end-col (length text)))))
      (table.insert doc.lines text))))

(fn blank [doc]
  (line doc [""]))

(fn heading [doc title]
  (blank doc)
  (let [label (.. " " title " ")
        rest (- width 2 (vim.fn.strdisplaywidth label))]
    (line doc [["──" hl.rule] [label hl.heading] [(string.rep "─" rest) hl.rule]]))
  (blank doc))

(fn note [doc text]
  (line doc [["  " nil] [text hl.label]]))

(fn bar-segments [fraction w group]
  (let [[filled track] (bar fraction w)]
    [[filled (or group hl.bar)] [track hl.track]]))

(fn concat-segments [...]
  (let [out []]
    (each [_ part (ipairs [...])]
      (each [_ seg (ipairs part)]
        (table.insert out seg)))
    out))

;; Ranges ---------------------------------------------------------------------------

(fn range-name [range]
  (if (= range :all) "all time"
      (= range 0) "today"
      (= range 1) "since yesterday"
      (.. "last " range " days")))

(fn range-args [range]
  (if (= range :all) ["--all"] ["--days" (tostring range)]))

(fn step-range [range direction]
  ;; The next shorter (-1) or longer (+1) of the preset ranges, or nil at either end.
  (let [rank #(if (= $1 :all) math.huge $1)
        here (rank range)
        [start stop] (if (> direction 0) [1 (length ranges)] [(length ranges) 1])]
    (var found nil)
    (for [i start stop direction &until found]
      (let [r (. ranges i)]
        (when (if (> direction 0) (> (rank r) here) (< (rank r) here))
          (set found r))))
    found))

(fn parse-range [arg]
  (if (= arg "all") :all
      (= arg "today") 0
      (string.match arg "^%d+$") (tonumber arg)))

(fn expand [cmd state]
  ;; The profile's command with {range}, {project} and {cwd} filled in.
  (let [replacement (pick-values 1 (string.gsub state.cwd "%%" "%%%%"))
        argv []]
    (each [_ arg (ipairs cmd)]
      (if (= arg "{range}") (vim.list_extend argv (range-args state.range))
          (= arg "{project}") (when state.project? (vim.list_extend argv ["--project" "."]))
          (table.insert argv (pick-values 1 (string.gsub arg "{cwd}" replacement)))))
    argv))

;; Dates ----------------------------------------------------------------------------

(fn day-at [ms]
  ;; Local noon of the day ms falls in, as os.time: adding days to it never crosses a
  ;; midnight, whatever the clocks do.
  (let [d (os.date "*t" (math.floor (/ ms 1000)))]
    (os.time {:year d.year :month d.month :day d.day :hour 12})))

(fn add-days [t n]
  (let [d (os.date "*t" t)]
    (os.time {:year d.year :month d.month :day (+ d.day n) :hour 12})))

(fn days-between [from to]
  ;; Every date from the day of from to the day of to, as "YYYY-MM-DD".
  (let [last (os.date "%Y-%m-%d" (day-at to))
        out []]
    (var t (day-at from))
    (var date (os.date "%Y-%m-%d" t))
    (while (and (<= date last) (< (length out) 10000))
      (table.insert out date)
      (set t (add-days t 1))
      (set date (os.date "%Y-%m-%d" t)))
    out))

(fn short-date [date]
  ;; "2026-10-04" -> "04 Oct"
  (let [(y m d) (string.match (or date "") "^(%d+)-(%d+)-(%d+)$")]
    (if y
      (os.date "%d %b" (os.time {:year (tonumber y) :month (tonumber m) :day (tonumber d) :hour 12}))
      (or date ""))))

(fn reset-time [at]
  ;; resetsAt as os.time: seconds or milliseconds since the epoch, or an ISO 8601 UTC time.
  (if (num? at)
    (if (> at 1e11) (math.floor (/ at 1000)) at)
    (= (type at) :string)
    (let [(y mo d h mi s) (string.match at "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)")]
      (when y
        ;; os.time reads the table as local time; shift by the zone offset to get UTC.
        (let [local-t (os.time {:year (tonumber y) :month (tonumber mo) :day (tonumber d)
                                :hour (tonumber h) :min (tonumber mi) :sec (or (tonumber s) 0)})
              now (os.time)
              offset (- (os.time (os.date "*t" now)) (os.time (os.date "!*t" now)))]
          (+ local-t offset))))))

(fn time-until [t now]
  ;; "in 2d 4h", "in 35m", "now"
  (let [left (- t now)]
    (if (<= left 60) "now"
        (< left 3600) (.. "in " (math.floor (/ left 60)) "m")
        (< left 86400) (.. "in " (math.floor (/ left 3600)) "h " (math.floor (/ (% left 3600) 60)) "m")
        (.. "in " (math.floor (/ left 86400)) "d " (math.floor (/ (% left 86400) 3600)) "h"))))

;; Sections -------------------------------------------------------------------------

(fn overview [doc stats days]
  (let [active (or stats.activeDays 0)
        cost (or stats.cost 0)
        label-w 13
        value-w 22
        cell (fn [label value group]
               [[(pad label label-w) hl.label] [(pad value value-w) (or group hl.value)]])]
    (heading doc "Overview")
    (line doc (concat-segments ["  "] (cell "Spent" (money cost) hl.money)
                               (cell "Sessions" (.. (grouped stats.sessions)
                                                    (if (and (num? stats.subagents) (> stats.subagents 0))
                                                      (.. " + " (grouped stats.subagents) " subagents")
                                                      "")))))
    (line doc (concat-segments ["  "]
                               (cell "Per day" (if (> active 0)
                                                 (.. (money (/ cost active)) " active")
                                                 "—")
                                     hl.money)
                               (cell "Prompts" (grouped stats.prompts))))
    (line doc (concat-segments ["  "]
                               (cell "Per prompt" (if (and (num? stats.prompts) (> stats.prompts 0))
                                                    (money (/ cost stats.prompts))
                                                    "—")
                                     hl.money)
                               (cell "Steps" (grouped stats.steps))))
    (line doc (concat-segments ["  "]
                               (cell "Active days" (if days (.. active " of " days) (tostring active)))
                               (cell "Streak" (plural (or stats.streak 0) "day"))))))

(fn tokens [doc stats]
  (let [t (or stats.tokens {})
        rows [["Input" (or t.input 0)]
              ["Output" (or t.output 0)]
              ["Reasoning" (or t.reasoning 0)]
              ["Cache read" (or (?. t :cache :read) 0)]
              ["Cache write" (or (?. t :cache :write) 0)]]
        total (accumulate [sum 0 _ [_ n] (ipairs rows)] (+ sum n))
        prompt-side (+ (or t.input 0) (or (?. t :cache :read) 0) (or (?. t :cache :write) 0))]
    (heading doc "Tokens")
    (each [_ [label n] (ipairs rows)]
      (let [fraction (if (> total 0) (/ n total) 0)]
        (line doc (concat-segments ["  " [(pad label 13) hl.label] [(lpad (compact n) 8) hl.value] "  "]
                                   (bar-segments fraction 30)
                                   ["  " [(lpad (percent fraction) 6) hl.label]]))))
    (line doc ["  " [(pad "Total" 13) hl.label] [(lpad (compact total) 8) hl.value]
               "  "
               [(if (> prompt-side 0)
                  (.. (percent (/ (or (?. t :cache :read) 0) prompt-side)) " of prompt tokens read from cache")
                  "")
                hl.label]])))

(fn model-name [entry]
  (let [m (or entry.model {})
        variant (when (and m.variant (not= m.variant "default")) m.variant)]
    (.. (or m.id "?") (if variant (.. " (" variant ")") ""))))

(fn models [doc stats]
  (let [list (vim.tbl_filter #(= (type $1) :table) (or stats.models []))
        total (accumulate [sum 0 _ m (ipairs list)] (+ sum (or m.cost 0)))
        top (accumulate [best 0 _ m (ipairs list)] (math.max best (or m.cost 0)))]
    (when (> (length list) 0)
      (table.sort list (fn [a b]
                         (if (= (or a.cost 0) (or b.cost 0))
                           (> (or a.steps 0) (or b.steps 0))
                           (> (or a.cost 0) (or b.cost 0)))))
      (heading doc "Spend by model")
      (let [name-w (math.min 30 (accumulate [w 5 _ m (ipairs list)]
                                  (math.max w (vim.fn.strdisplaywidth (model-name m)))))
            provider-w (math.min 12 (accumulate [w 8 _ m (ipairs list)]
                                      (math.max w (vim.fn.strdisplaywidth (or (?. m :model :providerID) "")))))
            bar-w (math.max 6 (- width 2 name-w 1 provider-w 1 8 1 1 6 1 6))]
        (line doc ["  " [(pad "Model" name-w) hl.label] " " [(pad "Provider" provider-w) hl.label]
                   " " [(lpad "Spent" 8) hl.label] " " [(pad "" (+ bar-w 1)) nil]
                   [(lpad "Share" 6) hl.label] " " [(lpad "Steps" 6) hl.label]])
        (each [_ m (ipairs list)]
          (let [cost (or m.cost 0)]
            (line doc (concat-segments
                        ["  " (pad (cut (model-name m) name-w) name-w)
                         " " [(pad (cut (or (?. m :model :providerID) "") provider-w) provider-w) hl.label]
                         " " [(lpad (money cost) 8) (if (> cost 0) hl.money hl.label)] " "]
                        (bar-segments (if (> top 0) (/ cost top) 0) bar-w)
                        [" " [(lpad (if (> total 0) (percent (/ cost total)) "—") 6) hl.label]
                         " " [(lpad (compact (or m.steps 0)) 6) hl.value]]))))))))

(fn buckets [stats]
  ;; Steps per day over the range, folded into at most chart-columns columns.
  ;; -> [{:from date :to date :steps n}], or nil without dates.
  (let [from (?. stats :range :from)
        to (?. stats :range :to)
        by-date (collect [_ a (ipairs (or stats.activity []))]
                  (when (and (= (type a) :table) a.date) (values a.date (or a.steps 0))))]
    (when (and (num? from) (num? to) (>= to from))
      (let [dates (days-between from to)
            size (math.ceil (/ (length dates) chart-columns))
            out []]
        (for [i 1 (length dates) size]
          (let [last (math.min (length dates) (+ i size -1))]
            (table.insert out {:from (. dates i) :to (. dates last)
                               :steps (accumulate [n 0 j (ipairs dates)]
                                        (if (and (>= j i) (<= j last))
                                          (+ n (or (. by-date (. dates j)) 0))
                                          n))})))
        (values out size)))))

(fn activity [doc stats]
  (let [(columns size) (buckets stats)]
    (when (and columns (> (length columns) 0))
      (let [peak (accumulate [best nil _ c (ipairs columns)]
                   (if (or (not best) (> c.steps best.steps)) c best))
            top (math.max 1 peak.steps)
            axis-w 7
            cell (fn [c row]
                   ;; One column's cell on row (1 is the bottom): eighths of a block.
                   (let [units (- (math.floor (+ (* (/ c.steps top) chart-height 8) 0.5))
                                  (* (- row 1) 8))]
                     (if (and (= row 1) (= c.steps 0)) ["·" hl.track]
                         (and (= row 1) (<= units 0)) ["▁" hl.bar]
                         (>= units 8) ["█" hl.bar]
                         (> units 0) [(. rising units) hl.bar]
                         [" " nil])))]
        (heading doc (.. "Activity · steps per " (if (= size 1) "day" (.. size " days"))))
        (for [row chart-height 1 -1]
          (let [axis (if (= row chart-height) (compact top) (= row 1) "0" "")
                segments [["  " nil] [(lpad axis (- axis-w 2)) hl.label] [" ┤" hl.rule]]]
            (each [_ c (ipairs columns)]
              (table.insert segments " ")
              (table.insert segments (cell c row)))
            (line doc segments)))
        (let [span (* 2 (length columns))
              first (short-date (. columns 1 :from))
              last (short-date (. columns (length columns) :to))]
          (line doc [(string.rep " " (+ axis-w 2))
                     [(.. (pad first (- span (vim.fn.strdisplaywidth last))) last) hl.label]]))
        (blank doc)
        (note doc (.. "Busiest: " (grouped peak.steps) " steps "
                      (if (= peak.from peak.to)
                        (.. "on " (short-date peak.from))
                        (.. (short-date peak.from) " – " (short-date peak.to)))))))))

(fn tools [doc stats]
  (let [list (vim.tbl_filter #(= (type $1) :table) (or (?. stats :tools :usage) []))
        totals (?. stats :tools :totals)]
    (when (> (length list) 0)
      (table.sort list #(> (or $1.calls 0) (or $2.calls 0)))
      (heading doc "Tools")
      (when (and (= (type totals) :table) (num? totals.calls) (> totals.calls 0))
        (note doc (.. (plural totals.calls "call") " · "
                      (percent (/ (or totals.succeeded 0) totals.calls)) " succeeded · "
                      (grouped (or totals.failed 0)) " failed"
                      (if (and (num? totals.unfinished) (> totals.unfinished 0))
                        (.. " · " (grouped totals.unfinished) " unfinished")
                        "")))
        (blank doc))
      (let [shown (vim.list_slice list 1 tool-rows)
            most (math.max 1 (or (?. shown 1 :calls) 1))
            name-w (math.min 16 (accumulate [w 4 _ t (ipairs shown)]
                                  (math.max w (vim.fn.strdisplaywidth (or t.name "")))))
            bar-w (- width 2 name-w 1 6 1 1 7 1 7 1 8)]
        (line doc ["  " [(pad "Tool" name-w) hl.label] " " [(lpad "Calls" 6) hl.label]
                   " " (pad "" (+ bar-w 1)) [(lpad "Failed" 7) hl.label] " "
                   [(lpad "Rate" 7) hl.label] " " [(lpad "Median" 8) hl.label]])
        (each [_ t (ipairs shown)]
          (let [calls (or t.calls 0)
                failed (or t.failed 0)
                rate (if (> calls 0) (/ failed calls) 0)
                group (if (>= rate 0.25) hl.bad (>= rate 0.1) hl.warn hl.label)]
            (line doc (concat-segments
                        ["  " (pad (cut (or t.name "?") name-w) name-w)
                         " " [(lpad (grouped calls) 6) hl.value] " "]
                        (bar-segments (/ calls most) bar-w)
                        [" " [(lpad (grouped failed) 7) (if (> failed 0) group hl.label)]
                         " " [(lpad (percent rate) 7) group]
                         " " [(lpad (duration t.durationP50) 8) hl.label]]))))
        (when (> (length list) tool-rows)
          (blank doc)
          (note doc (.. "and " (plural (- (length list) tool-rows) "more tool"))))))))

(fn limits [doc result now]
  ;; result: {:ok decoded} from :limits-cmd, {:failed true}, or nil when there is none.
  (when result
    (heading doc "Limits")
    (let [info (?. result :decoded :data)]
      (if result.failed
        (note doc "Not available yet: the limits command failed (details in the ACP debug log).")
        (not= (type info) :table)
        (note doc "Not signed in to OpenCode Console.")
        (do
          (var any false)
          (when (= (type info.go) :table)
            (each [_ window (ipairs [:rolling :weekly :monthly])]
              (let [meter (. info.go window)]
                (when (= (type meter) :table)
                  (set any true)
                  (let [pct (or meter.percent 0)
                        group (if (or meter.limited (>= pct 90)) hl.bad (>= pct 70) hl.warn hl.bar)
                        at (reset-time meter.resetsAt)]
                    (line doc (concat-segments
                                ["  " [(pad (.. "Go " window) 13) hl.label]]
                                (bar-segments (/ pct 100) 24 group)
                                [" " [(lpad (if meter.limited "limited" (.. (math.floor (+ pct 0.5)) "%")) 7)
                                      group]
                                 "  " [(if (and at (> at 0))
                                         (.. "resets " (time-until at now) " · " (os.date "%a %d %b %H:%M" at))
                                         "")
                                       hl.label]])))))))
          (each [i b (ipairs (if (= (type info.budgets) :table) info.budgets []))]
            (when (and (= (type b) :table) (num? b.spent) (num? b.limit))
              (set any true)
              (let [fraction (if (> b.limit 0) (/ b.spent b.limit) 0)
                    group (if (>= fraction 0.9) hl.bad (>= fraction 0.7) hl.warn hl.bar)
                    at (reset-time (or b.resetsAt b.resetAt))]
                (line doc (concat-segments
                            ["  " [(pad (cut (or b.name b.label (.. "Budget " i)) 12) 13) hl.label]]
                            (bar-segments fraction 24 group)
                            [" " [(lpad (percent fraction) 7) group]
                             "  " [(.. (money b.spent) " of " (money b.limit)) hl.money]
                             [(if b.picked " · in use" "") hl.label]
                             [(if (and at (> at 0)) (.. " · resets " (time-until at now)) "") hl.label]])))))
          (when (not any)
            (note doc "No allowance or budgets on this account."))
          (let [url (?. info :workspace :usageURL)]
            (when (= (type url) :string)
              (blank doc)
              (note doc url))))))))

(fn this-session [doc agent-name]
  ;; The running session's context and cost, from ACP's usage_update.
  (let [s (session.current)
        u (?. s :usage)]
    (when (and (session.alive? s) (= s.agent.name agent-name) u)
      (heading doc "This session")
      (let [model (accumulate [found nil _ o (ipairs (session.config s)) &until found]
                    (when (= o.category :model) o.display))]
        (when model
          (line doc ["  " [(pad "Model" 13) hl.label] [model hl.value]]))
        (when (and (num? u.size) (> u.size 0) (num? u.used))
          (let [fraction (/ u.used u.size)
                group (if (>= fraction 0.9) hl.bad (>= fraction 0.7) hl.warn hl.bar)]
            (line doc (concat-segments
                        ["  " [(pad "Context" 13) hl.label]]
                        (bar-segments fraction 24 group)
                        [" " [(lpad (.. (math.floor (* 100 fraction)) "%") 4) group]
                         "  " [(.. (compact u.used) " of " (compact u.size) " tokens") hl.label]]))))
        (when (num? u.cost)
          (line doc ["  " [(pad "Spent" 13) hl.label]
                     [(if (or (= u.currency "USD") (not u.currency))
                        (money u.cost)
                        (string.format "%.2f %s" u.cost u.currency))
                      hl.money]]))))))

(fn stats? [decoded]
  (and (= (type decoded) :table) (num? decoded.cost)
       (or (= (type decoded.tokens) :table) (= (type decoded.models) :table))))

(fn decode [text]
  (let [(ok decoded) (pcall vim.json.decode (or text "") {:luanil {:object true :array true}})]
    (when ok decoded)))

(fn document [state results]
  ;; state: {:agent :range :project? :cwd}; results: {:usage :limits}, each nil (no
  ;; command), :pending, or {:ok bool :text :decoded}.
  (let [doc (new-doc)
        now (os.time)
        usage results.usage
        stats (when (and (= (type usage) :table) usage.ok (stats? usage.decoded)) usage.decoded)
        days (when stats
               (let [from (?. stats :range :from)
                     to (?. stats :range :to)]
                 (when (and (num? from) (num? to))
                   (length (days-between from to)))))
        scope (if state.project? (vim.fn.fnamemodify state.cwd ":t") "all projects")]
    (line doc [[(.. "Usage · " state.agent) hl.title]])
    (line doc [[(.. (range-name state.range) " · " scope
                    (if (and stats days)
                      (.. " · " (short-date (os.date "%Y-%m-%d" (day-at stats.range.from)))
                          " – " (short-date (os.date "%Y-%m-%d" (day-at stats.range.to))))
                      "")
                    " · updated " (os.date "%H:%M" now))
                hl.label]])
    (line doc [["r refresh · < > range · p " hl.label]
               [(if state.project? "all projects" "this project") hl.label]
               [" · q close" hl.label]])
    (if (= usage nil)
      (do (heading doc "Account")
          (note doc (.. state.agent " has no usage command: set :usage-cmd in its vim.g.acp-agents profile.")))
      (= usage :pending)
      (do (blank doc) (note doc "Fetching…"))
      (not usage.ok)
      (do (heading doc "Account")
          (note doc (.. "The usage command failed: " (cut (vim.trim (or usage.text "")) 200))))
      stats
      (do (overview doc stats days)
          (tokens doc stats)
          (models doc stats)
          (activity doc stats)
          (tools doc stats))
      (do (heading doc "Account")
          (each [_ l (ipairs (vim.split (vim.trim (or usage.text "")) "\n" {:plain true}))]
            (line doc ["  " l]))))
    (when (not= results.limits :pending)
      (limits doc results.limits now))
    (this-session doc state.agent)
    (blank doc)
    doc))

;; The buffer -----------------------------------------------------------------------

(local states {})

(fn run [cmd state done]
  ;; done gets {:ok :text :decoded}. Failures go to the debug log too.
  (let [argv (expand cmd state)
        finish (fn [ok text]
                 (when (not ok)
                   (transport.debug "!!" (.. "usage: " (table.concat argv " ") ": " (vim.trim text))))
                 (done {: ok : text :decoded (when ok (decode text))}))
        (started err) (pcall vim.system argv {:cwd state.cwd :text true :timeout 30000}
                             (fn [obj]
                               (vim.schedule
                                 #(if (= obj.code 0)
                                    (finish true (or obj.stdout ""))
                                    (finish false (.. "exited " obj.code ": "
                                                      (or obj.stderr "") (or obj.stdout "")))))))]
    (when (not started)
      (vim.schedule #(finish false (.. "could not run " (. argv 1) ": " (tostring err)))))))

(fn paint [buf doc]
  (when (vim.api.nvim_buf_is_valid buf)
    (vim.api.nvim_set_option_value :modifiable true {:buf buf})
    (vim.api.nvim_buf_set_lines buf 0 -1 false doc.lines)
    (vim.api.nvim_set_option_value :modifiable false {:buf buf})
    (vim.api.nvim_set_option_value :modified false {:buf buf})
    (vim.api.nvim_buf_clear_namespace buf ns 0 -1)
    (each [_ m (ipairs doc.marks)]
      (when (> m.end-col m.col)
        (vim.api.nvim_buf_set_extmark buf ns m.row m.col {:end_col m.end-col :hl_group m.group})))))

(fn refresh [buf]
  ;; Runs the profile's commands and redraws as each answers. A refresh that starts
  ;; while another is out makes the older one's answers stale.
  (let [state (. states buf)]
    (when state
      (let [agent (agents.get state.agent)
            generation (+ (or state.generation 0) 1)
            results {:usage (when (?. agent :usage-cmd) :pending)
                     :limits (when (?. agent :limits-cmd) :pending)}
            redraw #(paint buf (document state results))]
        (set state.generation generation)
        (set state.results results)
        (redraw)
        (each [_ key (ipairs [:usage :limits])]
          (let [cmd (?. agent (.. key "-cmd"))]
            (when cmd
              (run cmd state
                   (fn [result]
                     (when (= generation state.generation)
                       (tset results key (if (= key :limits)
                                           (if result.ok result {:failed true})
                                           result))
                       (redraw)))))))))))

(fn keymaps [buf]
  (let [map (fn [key f desc]
              (vim.keymap.set :n key f {:buffer buf :nowait true : desc}))
        change (fn [f]
                 (fn []
                   (let [state (. states buf)]
                     (when state
                       (f state)
                       (refresh buf)))))]
    (map "r" #(refresh buf) "Refresh ACP usage")
    (map "<" (change #(set $1.range (or (step-range $1.range -1) $1.range))) "Shorter range")
    (map ">" (change #(set $1.range (or (step-range $1.range 1) $1.range))) "Longer range")
    (map "p" (change #(set $1.project? (not $1.project?))) "This project or every project")
    (map "q" #(if (> (length (vim.api.nvim_list_wins)) 1)
                (vim.api.nvim_win_close 0 false)
                (vim.cmd "bdelete"))
         "Close ACP usage")))

(fn ensure-buffer [agent-name]
  (let [name (.. "acp://usage/" agent-name)
        existing (vim.fn.bufnr name)]
    (if (> existing 0)
      existing
      (let [buf (vim.api.nvim_create_buf false true)]
        (vim.api.nvim_buf_set_name buf name)
        (tset (. vim.bo buf) :bufhidden :hide)
        (tset (. vim.bo buf) :swapfile false)
        (tset (. vim.bo buf) :filetype :acpusage)
        (keymaps buf)
        (vim.api.nvim_create_autocmd :BufWipeout
          {:buffer buf :once true :callback #(tset states buf nil)})
        buf))))

(fn show [buf mods]
  ;; Command modifiers choose the split, e.g. :vertical AcpUsage; without any it
  ;; opens below.
  (let [win (vim.fn.bufwinid buf)]
    (if (not= -1 win)
      (vim.api.nvim_set_current_win win)
      (do
        (vim.cmd (if (and mods (not= mods "")) (.. mods " split") "botright split"))
        (vim.api.nvim_win_set_buf 0 buf)
        (each [option value (pairs {:wrap false :number false :relativenumber false
                                    :signcolumn :no :list false :cursorline false
                                    :foldcolumn "0" :spell false})]
          (tset (. vim.wo 0) option value))))))

(fn parse-args [fargs]
  ;; [agent] [today|N|all] [project], in any order -> {:agent :range :project?}
  (var problem nil)
  (let [parsed {}]
    (each [_ arg (ipairs fargs)]
      (if (= arg "project") (set parsed.project? true)
          (parse-range arg) (set parsed.range (parse-range arg))
          (agents.get arg) (set parsed.agent arg)
          (set problem (.. "acp: '" arg "' is not an agent, a range (today, a number of days, all) "
                           "or project"))))
    (if problem (values nil problem) parsed)))

(fn default-agent []
  ;; The default agent if it has a usage command, else the first that does.
  (let [default (agents.default-name)]
    (if (?. (agents.get default) :usage-cmd)
      default
      (or (accumulate [found nil _ name (ipairs (agents.names)) &until found]
            (when (?. (agents.get name) :usage-cmd) name))
          default))))

(fn open [opts]
  ;; :AcpUsage [agent] [today|N|all] [project]  the usage of the agent of the running
  ;; session, else the default agent (or the first with a usage command), over the
  ;; last 30 days of every project.
  (let [(parsed problem) (parse-args opts.fargs)]
    (if (not parsed)
      (vim.notify problem vim.log.levels.WARN)
      (let [s (session.current)
            name (or parsed.agent (and s s.agent.name) (default-agent))
            buf (ensure-buffer name)
            old (. states buf)
            fresh? (or (not old) (> (length opts.fargs) 0))
            state {:agent name
                   :range (or parsed.range (if fresh? default-range old.range))
                   :project? (if fresh? (= parsed.project? true) old.project?)
                   :cwd (session.project-root)}]
        (tset states buf state)
        (show buf opts.mods)
        (refresh buf)))))

(fn complete [arglead _ _]
  (icollect [_ c (ipairs (vim.list_extend (agents.names) ["today" "7" "30" "90" "365" "all" "project"]))]
    (when (vim.startswith c arglead) c)))

{: open
 : complete
 : highlights
 : document
 : parse-args
 : step-range
 : expand
 : bar
 : grouped
 : compact
 : duration}
