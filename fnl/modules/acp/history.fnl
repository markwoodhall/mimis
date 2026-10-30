;; Choosing a past session to resume: ordering, labels and the picker.

(local ui (require :modules.acp.ui))

(fn parse-time [stamp]
  ;; Seconds since the epoch for an ISO 8601 timestamp, read as UTC (what agents send).
  (let [(y mo d h mi sec) (string.match (or stamp "") "^(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")]
    (when y
      (let [now (os.time)
            offset (- (os.time (os.date "*t" now)) (os.time (os.date "!*t" now)))]
        (+ offset (os.time {:year (tonumber y) :month (tonumber mo) :day (tonumber d)
                            :hour (tonumber h) :min (tonumber mi) :sec (tonumber sec)
                            :isdst false}))))))

(fn age [stamp now]
  (let [t (parse-time stamp)]
    (if (not t) ""
      (let [secs (- now t)]
        (if (< secs 60) "just now"
            (< secs 3600) (.. (math.floor (/ secs 60)) "m ago")
            (< secs 86400) (.. (math.floor (/ secs 3600)) "h ago")
            (< secs 604800) (.. (math.floor (/ secs 86400)) "d ago")
            (os.date "%Y-%m-%d" t))))))

(fn sort-recent [sessions]
  ;; Newest first; ISO timestamps order as strings, and sessions without one go last.
  (let [sorted (vim.deepcopy sessions)]
    (table.sort sorted (fn [a b] (> (or a.updated "") (or b.updated ""))))
    sorted))

(fn label [session now all?]
  ;; With sessions from every project, the directory says which one is which.
  (let [title (let [t (vim.trim (or (. (vim.split (or session.title "") "\n" {:plain true}) 1) ""))]
                (if (= t "") (.. "(untitled " (string.sub session.id 1 8) ")") t))
        parts [title]
        ago (age session.updated now)]
    (when (not= ago "") (table.insert parts ago))
    (when all? (table.insert parts (vim.fn.fnamemodify (or session.cwd "") ":~")))
    (table.concat parts " · ")))

(fn find [sessions id]
  ;; A session by its id, or by a prefix of it when that is unambiguous.
  (let [exact (accumulate [found nil _ s (ipairs sessions)] (if (= s.id id) s found))
        prefixed (icollect [_ s (ipairs sessions)] (when (vim.startswith s.id id) s))]
    (or exact (when (= 1 (length prefixed)) (. prefixed 1)))))

(fn select [sessions opts done]
  ;; opts: {:all? bool :id string}. done is called with the chosen session, or with nil
  ;; and the reason there is none.
  (if (not= opts.id nil)
    (let [found (find sessions opts.id)]
      (if found
        (done found)
        (done nil (.. "no session matches " opts.id))))
    (= 0 (length sessions))
    (done nil (if opts.all? "no sessions to resume" "no sessions to resume in this project"))
    (let [now (os.time)]
      (ui.select (sort-recent sessions)
                 {:prompt "Resume session: "
                  :format_item (fn [session] (label session now opts.all?))}
                 (fn [chosen]
                   (if chosen (done chosen) (done nil "no session chosen")))))))

{: parse-time
 : age
 : sort-recent
 : label
 : find
 : select}
