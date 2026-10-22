;; Session state and the turn state machine. Glues protocol messages to render and log.

(local transport (require :modules.acp.transport))
(local rpc (require :modules.acp.rpc))
(local protocol (require :modules.acp.protocol))
(local render (require :modules.acp.render))
(local log (require :modules.acp.log))

(local sessions {:current nil})

(fn project-root []
  (let [root (when (= 1 (vim.fn.exists "*FindRootDirectory"))
               (vim.fn.call "FindRootDirectory" []))]
    (if (and root (not= root ""))
      root
      (vim.fn.getcwd))))

(fn agent-cmd []
  (let [cmd (or vim.g.acp-agent-cmd ["claude-agent-acp"])]
    (if (= (type cmd) :string) (vim.split cmd " " {:trimempty true}) cmd)))

(fn alive? [s]
  (and s s.agent.proc (not s.ended) (not s.exited)))

;; Summary lines -------------------------------------------------------------

(local status-names
  {:pending "pending"
   :in_progress "running"
   :completed "done"
   :failed "failed"})

(fn short-title [s title]
  (let [first-line (or (. (vim.split (or title "tool") "\n" {:plain true}) 1) "tool")]
    (pick-values 1 (string.gsub first-line (vim.pesc (.. s.session.cwd "/")) ""))))

(fn tool-line [s tool]
  (.. "> tool: " (short-title s tool.title)
      " — " (or (. status-names tool.status) tool.status "pending")))

(fn permission-line [s block]
  (.. "> permission: " (short-title s block.title)
      " — " (or block.choice "awaiting choice")))

;; Activity ----------------------------------------------------------------------

(fn busy [s label]
  (when (not= (?. s.activity :label) label)
    (render.activity s label)))

(fn idle [s]
  (render.activity s nil))

(fn running? [s]
  (= s.turn.state :running))

;; Turn content ----------------------------------------------------------------

(fn last-block [turn]
  (. turn.blocks (length turn.blocks)))

(fn add-text [s text]
  (let [turn s.turn
        prev (last-block turn)]
    (when (running? s) (busy s "writing"))
    (if (and prev (= prev.type :text))
      (do
        (set prev.text (.. prev.text text))
        (render.append-text s text))
      ;; Text after a quoted line needs a blank line, or markdown folds it into the quote.
      (let [text (if prev (.. "\n" text) text)]
        (table.insert turn.blocks {:type :text : text})
        (render.append-text s text)))))

(fn add-line-block [s block]
  (table.insert s.turn.blocks block)
  (render.add-line s block))

(fn turn-active? [s]
  (not= s.turn.state :idle))

(fn still-running-label [s]
  ;; The most recent tool in this turn that hasn't finished, or "thinking".
  (var label "thinking")
  (each [_ id (ipairs (or s.turn.tool-ids []))]
    (let [tool (. s.tools id)]
      (when (and tool (or (= tool.status :pending) (= tool.status :in_progress)))
        (set label (.. "running " (short-title s tool.title))))))
  label)

(fn on-tool [s u]
  (let [tool {:title u.title :kind u.kind :status u.status}
        block {:type :line}]
    (set block.line (tool-line s tool))
    (set tool.block block)
    (tset s.tools u.id tool)
    (when (turn-active? s)
      (table.insert s.turn.tool-ids u.id)
      (add-line-block s block))
    (when (and (running? s) (or (= tool.status :pending) (= tool.status :in_progress)))
      (busy s (.. "running " (short-title s tool.title))))))

(fn on-tool-update [s u]
  (let [tool (. s.tools u.id)]
    (if (not tool)
      (on-tool s (vim.tbl_extend :force u {:status (or u.status :pending)}))
      (do
        (when u.title (set tool.title u.title))
        (when u.status (set tool.status u.status))
        (set tool.block.line (tool-line s tool))
        (render.update-line s tool.block)))
    (when (or (= u.status :completed) (= u.status :failed))
      (when (running? s) (busy s (still-running-label s)))
      (pcall vim.cmd "checktime"))))

;; Config options (model, mode, effort...) -----------------------------------------

(fn value-name [option]
  ;; A "Default" value shows what it resolves to when the agent says, e.g. "Opus 5.5".
  (var name (tostring option.current))
  (each [_ v (ipairs option.values)]
    (when (= v.value option.current)
      (set name (if (and v.description (string.match v.name "^Default"))
                  v.description
                  v.name))))
  name)

(fn config-option [s id]
  (accumulate [found nil _ o (ipairs (or (?. s :config) [])) &until found]
    (when (= o.id id) o)))

(fn config-by-category [s category]
  (accumulate [found nil _ o (ipairs (or (?. s :config) [])) &until found]
    (when (= o.category category) o)))

(fn config-summary [s]
  (table.concat (icollect [_ o (ipairs s.config)]
                  (.. o.name ": " o.display))
                " · "))

(fn note [s line]
  ;; A session event worth keeping: part of the turn if one is running, else straight to the log.
  (if (turn-active? s)
    (add-line-block s {:type :line : line})
    (do
      (render.add-line s {:type :line : line})
      (log.append-note s line))))

;; The settings and values last seen, kept on disk so :Acp can complete them
;; before a session exists.
(fn known-path []
  (.. (vim.fn.stdpath :data) "/acp-config.json"))

(fn remember [options]
  (let [known (icollect [_ o (ipairs options)]
                {:id o.id :values (icollect [_ v (ipairs o.values)] v.value)})
        encoded (vim.json.encode known)]
    (when (not= encoded sessions.known-encoded)
      (set sessions.known-encoded encoded)
      (pcall vim.fn.writefile [encoded] (known-path)))))

(fn known-config []
  ;; [{:id :values [value ...]}] from the running session, else from the last one.
  (let [live (?. sessions.current :config)]
    (if (and live (> (length live) 0))
      (icollect [_ o (ipairs live)]
        {:id o.id :values (icollect [_ v (ipairs o.values)] v.value)})
      (let [(ok known) (pcall #(vim.json.decode (table.concat (vim.fn.readfile (known-path)) "")))]
        (if (and ok (= (type known) :table)) known [])))))

(fn apply-config [s options announce?]
  (when (> (length options) 0)
    (each [_ o (ipairs options)]
      (set o.display (value-name o))
      (let [previous (config-option s o.id)]
        (when (and announce? previous (not= previous.current o.current))
          (note s (.. "> acp: " o.name " → " o.display)))))
    (set s.config options)
    (remember options)
    (vim.cmd "redrawstatus!")))

(fn validate [s id value]
  ;; nil if value can be set for id, else why not.
  (let [option (config-option s id)]
    (if (not option)
      (.. "unknown setting " id)
      (not (accumulate [ok false _ v (ipairs option.values)] (or ok (= v.value value))))
      (.. value " is not a value of " id))))

(fn set-config [s id value opts]
  ;; opts: {:quiet true} to skip the change note, {:done (fn [])} to run afterwards.
  (let [opts (or opts {})
        done (or opts.done #nil)]
    (if (not (alive? s))
      (vim.notify "acp: no running session" vim.log.levels.WARN)
      (rpc.request s.rpc protocol.methods.set-config-option
                   (protocol.set-config-params s.session.id id value)
                   (fn [err result]
                     (if err
                       (vim.notify (.. "acp: could not set " id ": " (or err.message "unknown"))
                                   vim.log.levels.WARN)
                       (apply-config s (protocol.parse-set-config-result result) (not opts.quiet)))
                     (done))))))

(fn configure [s requested opts]
  ;; requested: {id value}. Applied one at a time in the agent's option order, so a
  ;; setting that depends on another (effort on model) is checked against the new choices.
  (let [opts (or opts {})
        done (or opts.done #nil)
        warn (fn [message]
               (if opts.quiet
                 (render.status s message)
                 (vim.notify (.. "acp: " message) vim.log.levels.WARN)))
        pending (icollect [_ o (ipairs s.config)]
                  (let [value (. requested o.id)]
                    (when value [o.id value])))]
    (each [id _ (pairs requested)]
      (when (not (config-option s id))
        (warn (.. "unknown setting " id))))
    (fn step [i]
      (let [pair (. pending i)]
        (if (not pair)
          (done)
          (let [[id value] pair
                problem (validate s id value)]
            (if problem
              (do (warn problem) (step (+ i 1)))
              (= value (. (config-option s id) :current))
              (step (+ i 1))
              (set-config s id value {:quiet opts.quiet :done #(step (+ i 1))}))))))
    (step 1)))

(fn on-update [s params]
  (when (= (protocol.update-session-id params) s.session.id)
    (let [u (protocol.parse-update params)]
      (case (?. u :type)
        :text (when (turn-active? s) (add-text s u.text))
        :thought (when (running? s) (busy s "thinking"))
        :tool (on-tool s u)
        :tool-update (on-tool-update s u)
        :config (apply-config s u.options true)
        :usage (do
                 (set s.usage {:used u.used :size u.size})
                 (vim.cmd "redrawstatus!"))))))

;; Permissions -------------------------------------------------------------------

(fn answer-permission [s choice]
  (let [p s.permission]
    (when p
      (set s.permission nil)
      (set p.block.choice (if choice choice.name "cancelled"))
      (set p.block.line (permission-line s p.block))
      (render.update-line s p.block)
      (when (running? s) (busy s (still-running-label s)))
      (rpc.respond s.rpc p.id
                   (if choice
                     (protocol.permission-selected choice.id)
                     (protocol.permission-cancelled))))))

(fn on-permission [s params id]
  (let [p (protocol.parse-permission params)
        title (or p.title (?. (. s.tools (or p.tool-id "")) :title) "use a tool")
        block {:type :line : title}]
    (when s.permission
      ;; Only one prompt at a time; an older unanswered one is cancelled.
      (answer-permission s nil))
    (set block.line (permission-line s block))
    (if (turn-active? s)
      (add-line-block s block)
      (render.add-line s block))
    (set s.permission {: id : block})
    (when (running? s) (busy s "waiting for your permission"))
    (if (= s.turn.state :cancelling)
      (answer-permission s nil)
      (vim.ui.select p.options
                     {:prompt (.. "Agent wants to: " (short-title s title))
                      :format_item (fn [o] o.name)}
                     (fn [choice]
                       (when (and s.permission (= s.permission.id id))
                         (answer-permission s choice)))))))

;; Requests from the agent ---------------------------------------------------------

(fn on-request [s method params id]
  (if (= method protocol.methods.request-permission)
    (on-permission s params id)
    (rpc.method-not-found s.rpc id method)))

(fn on-notification [s method params]
  (when (= method protocol.methods.session-update)
    (on-update s params)))

;; Turns ---------------------------------------------------------------------------

(fn end-turn [s err result]
  (let [turn s.turn
        reason (if err
                 (.. "error: " (or err.message "unknown"))
                 (. (protocol.parse-prompt-result result) :stop-reason))]
    (when s.permission (answer-permission s nil))
    (add-line-block s {:type :line :line (.. "> stop: " reason)})
    (set s.turn {:state :idle})
    (idle s)
    (when (not (render.visible? s.buf))
      (vim.notify (.. "acp: agent finished (" reason ")")))
    (let [(ok e) (pcall log.append-turn s turn)]
      (when (not ok)
        (vim.notify (.. "acp: could not write session log: " (tostring e)) vim.log.levels.ERROR)))))

(fn send-prompt [s text]
  (if (not (alive? s))
    (vim.notify "acp: no running session" vim.log.levels.WARN)
    (not s.ready)
    (vim.notify "acp: session is still starting" vim.log.levels.WARN)
    (turn-active? s)
    (vim.notify "acp: a turn is already running" vim.log.levels.WARN)
    (let [turn {:state :running
                :prompt text
                :time (os.date "%H:%M")
                :blocks []
                :tool-ids []}]
      (set s.turn turn)
      (render.begin-turn s turn)
      (busy s "thinking")
      (rpc.request s.rpc protocol.methods.session-prompt
                   (protocol.prompt-params s.session.id text)
                   (fn [err result]
                     (when (= s.turn turn)
                       (end-turn s err result))))
      true)))

(fn cancel [s]
  (if (and s (= s.turn.state :running))
    (do
      (set s.turn.state :cancelling)
      (rpc.notify s.rpc protocol.methods.session-cancel (protocol.cancel-params s.session.id))
      (answer-permission s nil)
      (busy s "cancelling"))
    (vim.notify "acp: nothing to cancel")))

;; Lifecycle -------------------------------------------------------------------------

(fn on-exit [s code]
  (set s.exited true)
  (when (not s.ended)
    (rpc.fail-all s.rpc (.. "agent exited with code " code))
    (set s.permission nil)
    (set s.turn {:state :idle})
    (idle s)
    (render.status s (.. "agent exited with code " code
                         " — see " (transport.debug-path)))))

(fn handshake [s]
  (rpc.request s.rpc protocol.methods.initialize (protocol.initialize-params)
    (fn [err result]
      (if err
        (do
          (idle s)
          (render.status s (.. "initialize failed: " (or err.message "unknown"))))
        (let [info (protocol.parse-initialize result)]
          (set s.agent.info info)
          (busy s "creating session")
          (rpc.request s.rpc protocol.methods.session-new
                       (protocol.new-session-params s.session.cwd)
            (fn [err result]
              (if err
                (do
                  (idle s)
                  (render.status s (.. "session/new failed: " (or err.message "unknown")
                                       (if (> (length info.auth-methods) 0)
                                         (.. " (agent auth methods: "
                                             (table.concat info.auth-methods ", ") ")")
                                         ""))))
                (let [new-session (protocol.parse-new-session result)]
                  (set s.session.id new-session.id)
                  (apply-config s new-session.config false)
                  (when (next s.requested)
                    (busy s "applying settings"))
                  (configure s s.requested
                    {:quiet true
                     :done (fn []
                             (set s.ready true)
                             (idle s)
                             (render.status s (.. "connected to " (or info.name (. s.agent.cmd 1))
                                                  " · protocol v" (tostring info.protocol-version)
                                                  " · " s.session.cwd))
                             (when (> (length s.config) 0)
                               (render.status s (config-summary s))))}))))))))))

(fn start [requested]
  ;; requested: {setting value} applied once the session exists, before it takes prompts.
  (let [cwd (project-root)
        s {:agent {:cmd (agent-cmd)}
           :session {:id nil
                     : cwd
                     :project (vim.fn.fnamemodify cwd ":t")
                     :started (os.time)}
           :turn {:state :idle}
           :tools {}
           :config []
           :requested (or requested {})
           :ready false
           :usage nil
           :permission nil}]
    (log.init s)
    (render.create-buffers s)
    (set s.rpc (rpc.new {:send (fn [line] (transport.send s.agent.proc line))
                         :on-request (fn [method params id] (on-request s method params id))
                         :on-notification (fn [method params] (on-notification s method params))}))
    (let [(proc err) (transport.start s.agent.cmd cwd
                                      {:on-line (fn [line] (rpc.receive s.rpc line))
                                       :on-exit (fn [code] (on-exit s code))})]
      (set s.agent.proc proc)
      (set sessions.current s)
      (if proc
        (do
          (render.status s (.. "starting " (table.concat s.agent.cmd " ") "…"))
          (busy s "starting agent")
          (handshake s))
        (do
          (set s.exited true)
          (render.status s (.. "could not start agent: " (tostring err))))))
    s))

(fn stop [s]
  (when s
    (when (= s.turn.state :running) (cancel s))
    (set s.ended true)
    (when (and s.agent.proc (not s.exited))
      (transport.stop s.agent.proc))
    (render.wipe s)
    (when (= sessions.current s)
      (set sessions.current nil))
    (if s.log.path
      (vim.notify (.. "acp: session log " s.log.path))
      (vim.notify "acp: session ended"))))

(fn current []
  sessions.current)

(fn session-buffer? [s buf]
  (or (= buf s.buf) (= buf s.prompt-buf)))

(fn status-text []
  ;; Statusline segment. Model, mode and context use show in the session's own windows;
  ;; activity shows everywhere while the agent is working.
  (let [s sessions.current]
    (if (not s)
      ""
      (let [details (when (session-buffer? s (vim.api.nvim_get_current_buf))
                      (let [parts []
                            model (config-by-category s :model)
                            mode (config-by-category s :mode)]
                        (when model (table.insert parts model.display))
                        (when mode (table.insert parts mode.display))
                        (when (and s.usage s.usage.size (> s.usage.size 0))
                          (table.insert parts (.. (math.floor (/ (* 100 s.usage.used) s.usage.size)) "%")))
                        (when (> (length parts) 0) (table.concat parts " · "))))
            activity (render.activity-text s)
            text (if (and details activity) (.. details " | " activity)
                     (or details activity))]
        (if text
          (pick-values 1 (string.gsub (.. "[acp " text "]") "%%" "%%%%"))
          "")))))

(fn config [s]
  (or (?. s :config) []))

{: start
 : status-text
 : config
 : config-option
 : known-config
 : validate
 : set-config
 : configure
 : stop
 : send-prompt
 : cancel
 : current
 : alive?}
