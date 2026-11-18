;; :AcpThreads, a sidebar of every ACP thread: the session logs of every project, and the
;; sessions running now, grouped by project, each project's newest first, and the
;; projects in the order of their newest thread. <CR> on
;; one opens it in the window beside the sidebar, with that window's directory set to
;; the thread's project: a running one is shown, an earlier one resumed, and the others
;; keep running. n starts a new thread in the project of the one under the cursor, N
;; in a directory you choose (one with no threads yet, say), r renames one (its title
;; is otherwise the agent's, or its first prompt), R
;; reads the logs again, q closes. Running threads are marked: ● idle, ● working, and
;; ● waiting on you, kept up to date while the sidebar is open.
;;
;; A project shows its running threads and its 3 newest others; "… N more" under them
;; shows the rest on <CR>, and "… show fewer" hides them again.
;;
;; vim.g.acp-threads-width: the sidebar's width, 40 if not given.
;; vim.g.acp-threads-per-project: how many of a project's threads show, 3 if not given.

(local history (require :modules.acp.history))
(local log (require :modules.acp.log))
(local session (require :modules.acp.session))

(local ns (vim.api.nvim_create_namespace "acp-threads"))
(local state {:buf nil :win nil :main nil :logged [] :rows {} :timer nil :actions nil
              ;; Projects showing all their threads, by name.
              :expanded {}})

(fn threads []
  ;; The logged threads, with the running ones over them or added, newest first.
  (let [running (session.live)
        by-id {}
        found []]
    (each [_ t (ipairs state.logged)]
      (let [t (vim.tbl_extend :force {} t)]
        (when (not= t.id "") (tset by-id t.id t))
        (table.insert found t)))
    (each [_ s (ipairs running)]
      (let [t (. by-id (or s.session.id ""))]
        (if t
          (set t.live s)
          (table.insert found {:title (or s.session.name s.session.title "New thread") :id (or s.session.id "") :cwd s.session.cwd
                               :project s.session.project :updated "" :live s}))))
    (table.sort found (fn [a b]
                        (let [ta (if a.live (+ (os.time) 1) (or (history.parse-time a.updated) 0))
                              tb (if b.live (+ (os.time) 1) (or (history.parse-time b.updated) 0))]
                          (> ta tb))))
    found))

(fn by-project [all]
  ;; [{: project : threads}] in the order of each project's newest thread (threads are
  ;; newest first already, running ones first of all).
  (let [groups []
        index {}]
    (each [_ t (ipairs all)]
      (let [name (if (and t.project (not= t.project "")) t.project
                     (vim.fn.fnamemodify (or t.cwd "") ":t"))
            g (or (. index name)
                  (let [g {:project name :threads []}]
                    (tset index name g)
                    (table.insert groups g)
                    g))]
        (table.insert g.threads t)))
    groups))

(fn marker [t]
  ;; A running thread's dot, in the colours of the chat's tool rows: idle, working, or
  ;; waiting on you. nil for one that isn't running.
  (let [s t.live]
    (when s
      (if (session.waiting-on-you? s) :AcpThreadsWaiting
          (= s.turn.state :running) :AcpThreadsWorking
          :AcpThreadsLive))))

(fn shorten [text width]
  (if (> (vim.fn.strdisplaywidth text) width)
    (.. (vim.fn.strcharpart text 0 (math.max 1 (- width 1))) "…")
    text))

(fn when-short [t now]
  ;; How long ago, briefly, for the right of a thread's line.
  (let [at (history.parse-time t.updated)
        secs (when at (- now at))]
    (if t.live "now"
        (not secs) ""
        (< secs 3600) (.. (math.max 1 (math.floor (/ secs 60))) "m")
        (< secs 86400) (.. (math.floor (/ secs 3600)) "h")
        (< secs (* 7 86400)) (.. (math.floor (/ secs 86400)) "d")
        (< secs (* 35 86400)) (.. (math.floor (/ secs (* 7 86400))) "w")
        (os.date "%b %d" at))))

(local margin "  ")

(fn draw []
  ;; The sidebar's lines, with what each row stands for in state.rows. Laid out as the
  ;; chat is: projects as headings with a rule under them, like the agent's ## headings;
  ;; a thread's title with its age at the right, like a prompt's time; the thread shown
  ;; beside the sidebar in the agent's shade.
  (when (and state.buf (vim.api.nvim_buf_is_valid state.buf))
    (let [now (os.time)
          width (if (and state.win (vim.api.nvim_win_is_valid state.win))
                  (vim.api.nvim_win_get_width state.win)
                  (or vim.g.acp-threads-width 40))
          inner (- width (* 2 (length margin)))
          shown (when (and state.main (vim.api.nvim_win_is_valid state.main))
                  (vim.api.nvim_win_get_buf state.main))
          all (threads)
          lines []
          marks []
          line-marks []
          rows {}
          add (fn [text] (table.insert lines text) (- (length lines) 1))]
      ;; Threads · 12
      (let [row (add (.. margin "Threads · " (length all)))]
        (table.insert marks [row (length margin) (+ (length margin) 7) :AcpThreadsHeading])
        (table.insert marks [row (+ (length margin) 7) -1 :AcpThreadsMeta]))
      (each [_ g (ipairs (by-project all))]
        ;; Its running threads and its newest few, unless it's been expanded.
        (let [limit (or vim.g.acp-threads-per-project 3)
              running (length (vim.tbl_filter #$1.live g.threads))
              showing (if (. state.expanded g.project)
                        (length g.threads)
                        (math.min (length g.threads) (+ running limit)))]
          (set g.showing showing)
          (set g.hidden (- (length g.threads) showing)))
        ;; The project, its count, and a rule.
        (add "")
        (let [row (add (.. margin g.project "  " (length g.threads)))]
          (table.insert marks [row (length margin) (+ (length margin) (length g.project)) :AcpThreadsGroup])
          (table.insert marks [row (+ (length margin) (length g.project)) -1 :AcpThreadsMeta]))
        (let [row (add (.. margin (string.rep "─" inner)))]
          (table.insert marks [row 0 -1 :AcpThreadsRule]))
        (each [i t (ipairs g.threads) &until (> i g.showing)]
          (let [dot (marker t)
                age (when-short t now)
                room (- inner 2 (vim.fn.strdisplaywidth age) 2)
                title (shorten (vim.trim (or t.title "")) room)
                gap (string.rep " " (math.max 1 (- room (vim.fn.strdisplaywidth title) -2)))
                head (.. margin (if dot "● " "  "))
                row (add (.. head title gap age))
                current? (and t.live (= t.live.buf shown))]
            (tset rows (+ row 1) t)
            (when dot
              (table.insert marks [row (length margin) (+ (length margin) (length "●")) dot]))
            (table.insert marks [row (length head) (+ (length head) (length title))
                                 (if current? :AcpThreadsCurrent :AcpThreadsTitle)])
            (table.insert marks [row (- (length (. lines (+ row 1))) (length age)) -1 :AcpThreadsMeta])
            (when current? (table.insert line-marks [row :AcpThreadsShown]))))
        ;; <CR> on it shows the rest, or fewer again.
        (when (or (> g.hidden 0) (. state.expanded g.project))
          (let [row (add (.. margin "  " (if (> g.hidden 0) (.. "… " g.hidden " more") "… show fewer")))]
            (tset rows (+ row 1) {:toggle g.project})
            (table.insert marks [row 0 -1 :AcpThreadsMore]))))
      (set state.rows rows)
      ;; Drawn every second while open, so only rewritten when something changed.
      (let [key (.. (table.concat lines "\n") "\n"
                    (table.concat (icollect [_ [row from to g] (ipairs marks)]
                                    (.. row ":" from ":" to ":" g))
                                  " ")
                    (table.concat (icollect [_ [row g] (ipairs line-marks)] (.. row g)) " "))]
        (when (not= key state.key)
          (set state.key key)
          (tset (. vim.bo state.buf) :modifiable true)
          (vim.api.nvim_buf_set_lines state.buf 0 -1 false lines)
          (tset (. vim.bo state.buf) :modifiable false)
          (vim.api.nvim_buf_clear_namespace state.buf ns 0 -1)
          (each [_ [row group] (ipairs line-marks)]
            (vim.api.nvim_buf_set_extmark state.buf ns row 0 {:line_hl_group group}))
          (each [_ [row from to group] (ipairs marks)]
            (vim.api.nvim_buf_set_extmark state.buf ns row from
                                          {:end_col (if (= to -1) (length (. lines (+ row 1))) to)
                                           :hl_group group})))))))

(fn read-logs []
  (set state.logged (history.sessions (log.log-dir) nil true)))

(fn main-window []
  ;; The window threads open in: the one the sidebar was opened from, else another
  ;; one beside it, else a new one.
  (if (and state.main (vim.api.nvim_win_is_valid state.main) (not= state.main state.win))
    state.main
    (let [other (accumulate [found nil _ w (ipairs (vim.api.nvim_tabpage_list_wins 0)) &until found]
                  (when (and (not= w state.win)
                             (= "" (. (vim.api.nvim_win_get_config w) :relative)))
                    w))]
      (or other
          (do (vim.cmd "botright vsplit")
              (vim.api.nvim_get_current_win))))))

(fn under-cursor []
  (. state.rows (. (vim.api.nvim_win_get_cursor 0) 1)))

(fn in-project [t action]
  ;; Goes to the main window, sets its directory to t's project, then does action.
  (let [win (main-window)]
    (set state.main win)
    (vim.api.nvim_set_current_win win)
    (when (= 1 (vim.fn.isdirectory (or t.cwd "")))
      (vim.cmd (.. "lcd " (vim.fn.fnameescape t.cwd))))
    (action)
    (draw)))

(fn open-thread []
  (let [t (under-cursor)]
    (when t
      (if t.toggle
        (do (tset state.expanded t.toggle (not (. state.expanded t.toggle)))
            (draw))
        t.live
        (in-project t #(state.actions.show t.live))
        (= (or t.id "") "")
        (vim.notify "acp: this thread's log has no session id, so it can't be resumed"
                    vim.log.levels.WARN)
        (in-project t #(state.actions.resume t))))))

(fn new-thread []
  (let [t (under-cursor)]
    (when (and t (not t.toggle))
      (in-project t #(state.actions.new t)))))

(fn rename-thread []
  ;; Names the thread under the cursor: in its log, so the name lasts and wins over the
  ;; agent's titles. A running thread not logged yet takes it into its log's header.
  (let [t (under-cursor)]
    (when (and t (not t.toggle))
      (vim.ui.input {:prompt "Rename thread" :default (or t.title "")}
        (fn [answer]
          (let [name (when answer (vim.trim answer))]
            (when (and name (not= name ""))
              (let [path (or t.path (?. t :live :log :path))]
                (when t.live (set t.live.session.name name))
                (when path (log.set-name path name))
                (read-logs)
                (draw)))))))))

(fn new-thread-in []
  ;; A new thread in a directory you name, which needn't have had one before: asked
  ;; for with <Tab> completing directories, starting from the window beside's.
  (let [win (main-window)
        from (vim.fn.fnamemodify (vim.fn.getcwd win) ":~")]
    (vim.ui.input {:prompt "New thread in" :default (.. from "/") :completion "dir"}
      (fn [answer]
        (let [dir (when answer
                    (vim.fs.normalize (vim.fn.fnamemodify (vim.fn.expand (vim.trim answer)) ":p")))]
          (if (not dir) nil
              (= 0 (vim.fn.isdirectory dir))
              (vim.notify (.. "acp: no such directory: " answer) vim.log.levels.WARN)
              (let [cwd (pick-values 1 (dir:gsub "(.)/$" "%1"))
                    t {: cwd :project (vim.fn.fnamemodify cwd ":t")}]
                (in-project t #(state.actions.new t)))))))))

(fn stop-timer []
  (when state.timer
    (state.timer:stop)
    (state.timer:close)
    (set state.timer nil)))

(fn close []
  (stop-timer)
  (when (and state.win (vim.api.nvim_win_is_valid state.win))
    (vim.api.nvim_win_close state.win true))
  (set state.win nil))

(fn ensure-buffer []
  (when (not (and state.buf (vim.api.nvim_buf_is_valid state.buf)))
    (let [buf (vim.api.nvim_create_buf false true)
          map (fn [lhs f desc] (vim.keymap.set :n lhs f {:buffer buf :nowait true : desc}))]
      (vim.api.nvim_buf_set_name buf "acp://threads")
      (tset (. vim.bo buf) :bufhidden :hide)
      (tset (. vim.bo buf) :filetype :acpthreads)
      (map "<CR>" open-thread "Open this ACP thread")
      (map "n" new-thread "Start a new ACP thread in this thread's project")
      (map "N" new-thread-in "Start a new ACP thread in a directory you choose")
      (map "r" rename-thread "Rename the ACP thread under the cursor")
      (map "R" #(do (read-logs) (draw)) "Read the ACP session logs again")
      (map "q" close "Close the ACP threads sidebar")
      (vim.api.nvim_create_autocmd :BufEnter
        {:buffer buf
         :desc "Read the ACP session logs again"
         :callback #(do (read-logs) (draw) nil)})
      (set state.buf buf)))
  state.buf)

(fn window-options [win]
  (let [setlocal (fn [name value] (vim.api.nvim_set_option_value name value {:scope :local : win}))]
    (setlocal :number false)
    (setlocal :relativenumber false)
    (setlocal :signcolumn "no")
    (setlocal :foldcolumn "0")
    (setlocal :statuscolumn "")
    (setlocal :wrap false)
    (setlocal :cursorline true)
    (setlocal :winfixwidth true)
    (setlocal :list false)
    ;; A panel beside the chat, in the statusline's darker shade, its cursor row the
    ;; grey of the chat's input.
    (setlocal :winhighlight (.. "Normal:AcpThreadsNormal,NormalNC:AcpThreadsNormal,"
                                "EndOfBuffer:AcpThreadsNormal,CursorLine:AcpThreadsCursor,"
                                "WinSeparator:AcpThreadsSeparator"))
    (setlocal :fillchars "eob: ")))

(fn open [actions]
  ;; :AcpThreads opens the sidebar, or closes it if it's open. actions: {:show s,
  ;; :resume thread, :new thread}, each run in the thread's window and directory.
  (set state.actions actions)
  (if (and state.win (vim.api.nvim_win_is_valid state.win))
    (close)
    (do
      (set state.main (vim.api.nvim_get_current_win))
      (read-logs)
      (vim.cmd (.. "topleft vertical " (or vim.g.acp-threads-width 40) "split"))
      (set state.win (vim.api.nvim_get_current_win))
      (vim.api.nvim_win_set_buf state.win (ensure-buffer))
      (window-options state.win)
      (draw)
      ;; Running threads' state changes as they work: kept current while it's open.
      (stop-timer)
      (set state.timer (vim.uv.new_timer))
      (state.timer:start 1000 1000
                         (vim.schedule_wrap
                           #(if (and state.win (vim.api.nvim_win_is_valid state.win))
                              (draw)
                              (stop-timer)))))))

{: open
 : close}
