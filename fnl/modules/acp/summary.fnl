;; A markdown summary of the session logs: browse them, gf their log, resume them.

(local agents (require :modules.acp.agents))
(local history (require :modules.acp.history))
(local log (require :modules.acp.log))
(local render (require :modules.acp.render))

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

(fn read [path]
  (let [lines (vim.fn.readfile path)
        meta (frontmatter lines)
        parsed (turns lines)
        first-turn (. parsed 1)
        id (or meta.session "")
        title (shorten (first-nonblank (or (?. first-turn :prompt) [])) title-width)
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
  (let [found (icollect [_ path (ipairs (vim.fn.glob (.. dir "/*.md") false true))]
                (let [(ok session) (pcall read path)]
                  (when (and ok (or all? (in-project? root session.cwd)))
                    session)))
        sorted (history.sort-recent found)
        seen {}
        unique []]
    (each [_ session (ipairs sorted)]
      (when (not (. seen session.key))
        (tset seen session.key true)
        (table.insert unique session)))
    unique))

(fn display-date [date]
  (pick-values 1 (string.gsub date "T" " ")))

(fn summary-lines [sessions opts]
  (let [all? opts.all?
        name (if all? "all projects" (vim.fn.fnamemodify (or opts.root "") ":t"))
        now (os.time)
        lines [(.. "# ACP sessions — " name) ""]]
    (table.insert lines
                  (.. "_" (length sessions)
                      (if (= 1 (length sessions)) " session" " sessions")
                      " · generated " (os.date "%Y-%m-%d %H:%M") "_"))
    (when (> (length sessions) 0)
      (vim.list_extend lines ["" "_<CR> resumes a session · `gf` opens its log_"]))
    (if (= 0 (length sessions))
      (vim.list_extend lines [""
                              (.. "No session logs in "
                                  (vim.fn.fnamemodify (log.log-dir) ":~") ".")
                              ""])
      (each [i session (ipairs sessions)]
        (let [parts []
              ago (history.age session.updated now)]
          (vim.list_extend lines ["" "---" "" (.. "## " i ". " session.title) ""])
          (table.insert lines (.. "`" (vim.fn.fnamemodify session.path ":~") "`"))
          (when (not= session.date "") (table.insert parts (display-date session.date)))
          (when (not= ago "") (table.insert parts ago))
          (table.insert parts (.. session.turns
                                  (if (= 1 session.turns) " turn" " turns")))
          (when all? (table.insert parts (.. session.project " · "
                                               (vim.fn.fnamemodify session.cwd ":~"))))
          (table.insert lines (.. "_" (table.concat parts " · ") "_"))
          (when (not= session.preview "")
            (vim.list_extend lines ["" (.. "> " session.preview)]))
          (when (not= session.id "")
            (vim.list_extend lines ["" (.. "[Resume this session](acp://resume/" session.id ")")])))))
    lines))

(fn resume [session]
  (when session
    (let [name (when (and session.agent-name (agents.get session.agent-name))
                 session.agent-name)
          args (if name [name session.id] [session.id])]
      (vim.cmd (.. "AcpResume "
                   (table.concat (icollect [_ a (ipairs args)] (vim.fn.fnameescape a)) " "))))))

(fn map-resume [buf sessions]
  ;; <CR> on a resume link resumes it, everywhere else <CR> is itself.
  (let [by-id {}]
    (each [_ session (ipairs sessions)]
      (when (not= session.id "") (tset by-id session.id session)))
    (vim.keymap.set :n "<CR>"
                    (fn []
                      (let [id (string.match (vim.api.nvim_get_current_line)
                                             "acp://resume/([^)]+)")
                            session (when id (. by-id id))]
                        (if session
                          (do (vim.schedule #(resume session)) "")
                          "<CR>")))
                    {:buffer buf
                     :expr true
                     :desc "Resume the ACP session on this line"})))

(fn buffer-name [opts]
  (.. "acp://summary/" (if opts.all? "all" (vim.fn.fnamemodify (or opts.root "") ":t"))))

(fn ensure-buffer [name]
  (let [existing (vim.fn.bufnr name)]
    (if (> existing 0)
      existing
      (let [buf (vim.api.nvim_create_buf false true)]
        (vim.api.nvim_buf_set_name buf name)
        (tset (. vim.bo buf) :bufhidden :hide)
        (tset (. vim.bo buf) :swapfile false)
        buf))))

(fn fill [buf lines]
  (vim.api.nvim_set_option_value :modifiable true {:buf buf})
  (vim.api.nvim_buf_set_lines buf 0 -1 false lines)
  (vim.api.nvim_set_option_value :modifiable false {:buf buf})
  (vim.api.nvim_set_option_value :modified false {:buf buf}))

(fn show [buf mods]
  ;; Like the chat: command modifiers choose the split, e.g. :botright AcpSummary
  ;; or :vertical AcpSummary. Without any, the summary opens as a right-hand split.
  (let [win (vim.fn.bufwinid buf)]
    (if (not= -1 win)
      (vim.api.nvim_set_current_win win)
      (do
        (vim.cmd (if (and mods (not= mods "")) (.. mods " split") "botright vsplit"))
        (vim.api.nvim_win_set_buf 0 buf)
        (tset (. vim.wo 0) :wrap true)
        (tset (. vim.wo 0) :linebreak true)
        (tset (. vim.wo 0) :number false)
        (tset (. vim.wo 0) :relativenumber false)
        (tset (. vim.wo 0) :conceallevel 0)
        (tset (. vim.wo 0) :foldmethod :manual)))))

(fn open [opts]
  (let [all? opts.all?
        root (or opts.root (vim.fn.getcwd))
        found (sessions (log.log-dir) root all?)
        buf (ensure-buffer (buffer-name {: all? : root}))]
    (fill buf (summary-lines found {: all? : root}))
    (render.markdown buf)
    (map-resume buf found)
    (show buf opts.mods)))

{: open
 : read
 : sessions
 : summary-lines
 : frontmatter
 : turns
 : in-project?}
