;; :AcpThreads, a sidebar of every ACP thread: the session logs of every project, and the
;; sessions running now, grouped by project, each project's newest first, and the
;; projects in the order of their newest thread. <CR> on
;; one opens it in the window beside the sidebar, with that window's directory set to
;; the thread's project: a running one is shown, an earlier one resumed, and the others
;; keep running. n starts a new thread in the project of the one under the cursor, a
;; does too after asking for its agent and model (from those the agent last offered), N
;; in a directory you choose (one with no threads yet, say), r renames one (its title
;; is otherwise the agent's, or its first prompt), d deletes one, or on a project's
;; heading all of its threads (not running ones), R
;; reads the logs again, q closes. Running threads are marked: ● idle, ● working, and
;; ● waiting on you, kept up to date while the sidebar is open. Under a running thread
;; are the agents it delegated to, while their sessions are open, with how each is
;; getting on; <CR> on one goes to its chat (gW goes to whichever chat waits on you).
;; A thread one of them is waiting in is marked as waiting on you too.
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
  ;; waiting on you, itself or an agent it delegated to. nil for one that isn't running.
  (let [s t.live]
    (when s
      (if (or (session.waiting-on-you? s)
              (accumulate [waiting false _ child (ipairs (session.children s))]
                (or waiting (and (not child.ended) (session.waiting-on-you? child)))))
        :AcpThreadsWaiting
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

;; Each agent's glyph, before its threads' titles in its colour: Claude's starburst
;; and OpenCode's square; any other agent's first letter. vim.g.acp-agent-icons, agent
;; name to {:glyph :colour}, changes them.
(local agent-glyphs {:claude {:glyph "✻" :colour "#D97757"}
                     :opencode {:glyph "▣" :colour "#A6ADC8"}})

(fn agent-glyph [name]
  ;; The glyph for agent name, and its highlight group.
  (let [name (or name "")
        look (vim.tbl_extend :force
                             {:glyph (string.upper (or (name:match "%w") "?"))}
                             (or (. agent-glyphs name) {})
                             (or (?. vim.g.acp-agent-icons name) {}))
        group (.. "AcpThreadsAgent" (pick-values 1 (name:gsub "%W" "")))]
    (vim.api.nvim_set_hl 0 group (if look.colour
                                   {:fg look.colour :bold true :default false}
                                   {:link :AcpThreadsMeta :default false}))
    (values look.glyph group)))

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
          ;; The heading stands for the project: d there deletes its threads.
          (tset rows (+ row 1) {:heading g})
          (table.insert marks [row (length margin) (+ (length margin) (length g.project)) :AcpThreadsGroup])
          (table.insert marks [row (+ (length margin) (length g.project)) -1 :AcpThreadsMeta]))
        (let [row (add (.. margin (string.rep "─" inner)))]
          (table.insert marks [row 0 -1 :AcpThreadsRule]))
        (each [i t (ipairs g.threads) &until (> i g.showing)]
          (let [dot (marker t)
                age (when-short t now)
                (glyph glyph-group) (agent-glyph (or (?. t :live :agent :name) t.agent-name))
                ;; Room for the agent's glyph too, and a space.
                room (- inner 2 (vim.fn.strdisplaywidth glyph) 1 (vim.fn.strdisplaywidth age) 2)
                title (shorten (vim.trim (or t.title "")) room)
                gap (string.rep " " (math.max 1 (- room (vim.fn.strdisplaywidth title) -2)))
                before (.. margin (if dot "● " "  "))
                head (.. before glyph " ")
                row (add (.. head title gap age))
                current? (and t.live (= t.live.buf shown))]
            (tset rows (+ row 1) t)
            (table.insert marks [row (length before) (+ (length before) (length glyph)) glyph-group])
            (when dot
              (table.insert marks [row (length margin) (+ (length margin) (length "●")) dot]))
            (table.insert marks [row (length head) (+ (length head) (length title))
                                 (if current? :AcpThreadsCurrent :AcpThreadsTitle)])
            (table.insert marks [row (- (length (. lines (+ row 1))) (length age)) -1 :AcpThreadsMeta])
            (when current? (table.insert line-marks [row :AcpThreadsShown]))
            ;; The agents it delegated to, under it while their sessions are open: <CR>
            ;; on one goes to its chat, where it may be waiting on you.
            (each [_ child (ipairs (if t.live (session.children t.live) []))]
              (when (not child.ended)
                (let [dot (marker {:live child})
                      (glyph glyph-group) (agent-glyph child.agent.name)
                      st (session.state child)
                      word (case st
                             :waiting_for_user "waiting on you"
                             :running "working"
                             :starting "starting"
                             :idle "done"
                             other (tostring other))
                      indent (.. margin "  ↳ ")
                      before (.. indent (if dot "● " "  "))
                      head (.. before glyph " ")
                      room (- inner 4 2 (vim.fn.strdisplaywidth glyph) 1 (vim.fn.strdisplaywidth word) 2)
                      title child.session.title
                      label (shorten (.. (or child.label child.agent.name)
                                         (if title (.. " · " title) ""))
                                     room)
                      gap (string.rep " " (math.max 1 (- room (vim.fn.strdisplaywidth label) -2)))
                      row (add (.. head label gap word))]
                  (tset rows (+ row 1) {: child :cwd child.session.cwd})
                  (table.insert marks [row (length margin) (length indent) :AcpThreadsMeta])
                  (when dot
                    (table.insert marks [row (length indent) (+ (length indent) (length "●")) dot]))
                  (table.insert marks [row (length before) (+ (length before) (length glyph)) glyph-group])
                  (table.insert marks [row (length head) (+ (length head) (length label)) :AcpThreadsTitle])
                  (table.insert marks [row (- (length (. lines (+ row 1))) (length word)) -1
                                       (if (= st :waiting_for_user) :AcpThreadsWaiting :AcpThreadsMeta)]))))))
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
      (if (or t.toggle t.heading)
        ;; Its "… more" line, or its heading: all of a project's threads, or fewer.
        (let [name (or t.toggle t.heading.project)]
          (tset state.expanded name (not (. state.expanded name)))
          (draw))
        t.live
        (in-project t #(state.actions.show t.live))
        t.child
        (in-project t #(state.actions.show t.child))
        (= (or t.id "") "")
        (vim.notify "acp: this thread's log has no session id, so it can't be resumed"
                    vim.log.levels.WARN)
        (in-project t #(state.actions.resume t))))))

(fn new-thread [choose?]
  ;; On a thread or its project's heading: a new thread in that project, with choose?
  ;; with the agent and model you pick.
  (let [t (under-cursor)
        t (if (?. t :heading) (. t.heading.threads 1) t)]
    (when (and t (not t.toggle) (not t.child))
      (if choose?
        (state.actions.choose t
          (fn [name settings]
            (in-project t #(state.actions.new t name settings))))
        (in-project t #(state.actions.new t))))))

(fn log-paths [threads]
  ;; Every log of these threads: a resumed one can have several, so by session id (by
  ;; path for one without).
  (let [ids {}
        paths {}]
    (each [_ t (ipairs threads)]
      (if (not= (or t.id "") "") (tset ids t.id true))
      (when t.path (tset paths t.path true)))
    (icollect [_ path (ipairs (vim.fn.glob (.. (log.log-dir) "/*.md") true true))]
      (let [meta (history.frontmatter (vim.fn.readfile path "" 30))]
        (when (or (. paths path) (. ids (or meta.session ""))) path)))))

(fn delete-threads [threads what]
  ;; Deletes the threads' logs, once you've said so: they're gone for good, from the
  ;; sidebar and :AcpResume's history. The agent's own record of the session, if it
  ;; keeps one, stays.
  (let [paths (log-paths threads)]
    (vim.ui.select ["Delete" "Keep"]
                   {:prompt (.. "Delete " what "? Its log"
                                (if (= 1 (length paths)) "" "s")
                                " can't be brought back")}
      (fn [choice]
        (when (= choice "Delete")
          (each [_ path (ipairs paths)]
            (vim.fn.delete path))
          (read-logs)
          (draw)
          (vim.notify (.. "acp: deleted " (length paths)
                          (if (= 1 (length paths)) " log" " logs"))))))))

(fn delete-under-cursor []
  ;; d: the thread under the cursor, or on a heading every thread of its project. A
  ;; running thread is left alone: its log is still being written.
  (let [t (under-cursor)]
    (when (and t (not t.toggle) (not t.child))
      (if t.heading
        (let [g t.heading
              done (vim.tbl_filter #(not $1.live) g.threads)
              running (- (length g.threads) (length done))]
          (if (= 0 (length done))
            (vim.notify (.. "acp: every thread in " g.project " is running; :AcpStop one to delete it"))
            (delete-threads done (.. (length done) (if (= 1 (length done)) " thread" " threads")
                                     " in " g.project
                                     (if (> running 0) (.. " (not the " running " running)") "")))))
        t.live
        (vim.notify "acp: that thread is running; :AcpStop it, then delete it"
                    vim.log.levels.WARN)
        (delete-threads [t] (.. "\"" (or t.title "this thread") "\""))))))

(fn rename-thread []
  ;; Names the thread under the cursor: in its log, so the name lasts and wins over the
  ;; agent's titles. A running thread not logged yet takes it into its log's header.
  (let [t (under-cursor)]
    (when (and t (not t.toggle) (not t.heading) (not t.child))
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
      (map "n" #(new-thread) "Start a new ACP thread in this thread's project")
      (map "a" #(new-thread true) "Start a new ACP thread in this project, choosing its agent and model")
      (map "N" new-thread-in "Start a new ACP thread in a directory you choose")
      (map "r" rename-thread "Rename the ACP thread under the cursor")
      (map "d" delete-under-cursor "Delete the ACP thread, or on a heading the project's threads")
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
  ;; :resume thread, :new thread [agent settings]}, each run in the thread's window and
  ;; directory, and :choose thread done, asking for an agent and settings for :new.
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
