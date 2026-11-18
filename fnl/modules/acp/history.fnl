;; Past sessions: reading their logs, ordering and labelling them, and the picker for
;; resuming one.

(local agents (require :modules.acp.agents))


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
      (vim.ui.select (sort-recent sessions)
                     {:prompt "Resume session: "
                      :format_item (fn [session] (label session now opts.all?))}
                     (fn [chosen]
                       (if chosen (done chosen) (done nil "no session chosen")))))))

;; Reading the session logs ------------------------------------------------------

(local title-width 80)
(local preview-width 240)
(local preview-lines 4)

(fn trim [text]
  (vim.trim (or text "")))

(fn shorten [text width]
  ;; One line, whitespace collapsed, cut to width characters with "…".
  (let [text (trim (pick-values 1 (string.gsub (or text "") "%s+" " ")))]
    (if (> (vim.fn.strchars text) width)
      (.. (vim.fn.strcharpart text 0 (- width 1)) "…")
      text)))

(fn frontmatter [lines]
  ;; The "---" header of a log, as a table.
  (let [meta {}]
    (when (= "---" (trim (. lines 1)))
      (var i 2)
      (var done false)
      (while (and (<= i (length lines)) (not done))
        (let [line (. lines i)]
          (if (= "---" (trim line))
            (set done true)
            (let [(key value) (string.match line "^(%w[%w_-]*):%s*(.*)$")]
              (when key
                (tset meta key (trim value)))))
          (set i (+ i 1)))))
    meta))

(fn you-heading? [line]
  (or (= line "## You") (not= nil (string.match line "^## You — %d%d:%d%d$"))))

(fn turns [lines]
  ;; The turns in a log: {:prompt [line...] :agent [line...]}.
  (let [found []]
    (var current nil)
    (var in-agent false)
    (each [_ line (ipairs lines)]
      (if (you-heading? line)
        (do
          (set current {:prompt [] :agent []})
          (table.insert found current)
          (set in-agent false))
        (and current (= line "## Agent"))
        (set in-agent true)
        current
        (table.insert (if in-agent current.agent current.prompt) line)))
    found))

(fn first-nonblank [lines]
  (var found "")
  (each [_ line (ipairs (or lines [])) &until (not= found "")]
    (set found (trim line)))
  found)

(fn agent-name [command]
  ;; A log records the agent's command, not its configured name. Match it back to
  ;; the profile it came from, so resuming starts the same agent.
  (when (not= (trim command) "")
    (accumulate [found nil _ name (ipairs (agents.names)) &until found]
      (let [agent (agents.get name)]
        (when (and agent (= command (table.concat agent.cmd " "))) name)))))

(fn preview [turn]
  ;; The first prose in the agent's reply, skipping tool lines, thinking and fences.
  (let [parts []]
    (each [_ line (ipairs (or (?. turn :agent) []))]
      (let [text (trim line)]
        (when (and (not= text "")
                   (not (vim.startswith text ">"))
                   (not (vim.startswith text "#"))
                   (not (vim.startswith text "```"))
                   (not (vim.startswith text "~~~")))
          (table.insert parts text))))
    (shorten (table.concat (vim.list_slice parts 1 (math.min preview-lines (length parts))) " ")
             preview-width)))

(fn agent-title [lines]
  ;; The latest title the agent gave the session: in the header when the log began,
  ;; and as a note each time it changed.
  (accumulate [found nil _ line (ipairs lines)]
    (or (line:match "^> acp: title: (.+)$") found)))

(fn read [path]
  ;; A thread's title is the name you gave it, else the agent's latest, else its first
  ;; prompt.
  (let [lines (vim.fn.readfile path)
        meta (frontmatter lines)
        parsed (turns lines)
        first-turn (. parsed 1)
        id (or meta.session "")
        given (or (when (not= (or meta.name "") "") meta.name)
                  (agent-title lines)
                  (when (not= (or meta.title "") "") meta.title))
        title (shorten (or given (first-nonblank (or (?. first-turn :prompt) []))) title-width)
        date (or meta.date "")
        updated (if (and (not= date "") (not (string.match date "T%d+:%d+:%d+")))
                  (.. date ":00")
                  date)]
    {:path path
     :id id
     :key (if (= id "") path id)
     :title (if (= title "")
               (.. "(untitled " (if (= id "") (vim.fn.fnamemodify path ":t:r") (string.sub id 1 8)) ")")
               title)
     :preview (preview first-turn)
     :turns (length parsed)
     :date date
     :updated updated
     :cwd (or meta.cwd "")
     :project (or meta.project (vim.fn.fnamemodify (or meta.cwd "") ":t"))
     :agent (or meta.agent "")
     :agent-name (or meta.agent-name (agent-name (or meta.agent "")))}))

(fn normalize [path]
  (when (not= (trim path) "")
    (pick-values 1 (string.gsub (vim.fn.simplify (vim.fn.fnamemodify path ":p")) "/+$" ""))))

(fn in-project? [root cwd]
  (let [root (normalize root)
        cwd (normalize cwd)]
    (and root cwd
         (or (= cwd root) (= root "") (vim.startswith cwd (.. root "/"))))))

(fn sessions [dir root all?]
  ;; The logged sessions for root (or every project's), newest first and one per id.
  ;; Every log, whatever 'wildignore' leaves out of completion.
  (let [found (icollect [_ path (ipairs (vim.fn.glob (.. dir "/*.md") true true))]
                (let [(ok session) (pcall read path)]
                  (when (and ok (or all? (in-project? root session.cwd)))
                    session)))
        sorted (sort-recent found)
        seen {}
        unique []]
    (each [_ session (ipairs sorted)]
      (when (not (. seen session.key))
        (tset seen session.key true)
        (table.insert unique session)))
    unique))

{: parse-time
 : age
 : sort-recent
 : label
 : find
 : select
 : read
 : sessions
 : frontmatter
 : turns
 : in-project?}
