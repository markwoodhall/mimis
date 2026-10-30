;; Session state and the turn state machine. Glues protocol messages to render and log.

(local transport (require :modules.acp.transport))
(local rpc (require :modules.acp.rpc))
(local protocol (require :modules.acp.protocol))
(local render (require :modules.acp.render))
(local log (require :modules.acp.log))
(local history (require :modules.acp.history))
(local credits (require :modules.acp.credits))
(local form (require :modules.acp.form))
(local sandbox (require :modules.acp.sandbox))

(local sessions {:current nil})

(fn project-root []
  (let [root (when (= 1 (vim.fn.exists "*FindRootDirectory"))
               (vim.fn.call "FindRootDirectory" []))]
    (if (and root (not= root ""))
      root
      (vim.fn.getcwd))))

(fn alive? [s]
  (and s s.agent.proc (not s.ended) (not s.exited)))

;; Summary lines -------------------------------------------------------------

(local status-names
  {:pending "pending"
   :in_progress "running"
   :completed "done"
   :failed "failed"})

(local title-width 72)
(local activity-width 40)

(fn short-title [s title width]
  ;; First line only, project paths made relative, cut to width characters with "…".
  ;; Returns the short title and whether anything was cut.
  (let [width (or width title-width)
        lines (vim.split (or title "tool") "\n" {:plain true})
        first-line (pick-values 1 (string.gsub (or (. lines 1) "tool")
                                               (vim.pesc (.. s.session.cwd "/")) ""))
        multi-line? (> (length (vim.tbl_filter #(not= (vim.trim $1) "") lines)) 1)]
    (if (> (vim.fn.strchars first-line) width)
      (values (.. (vim.trim (vim.fn.strcharpart first-line 0 (- width 1))) "…") true)
      multi-line?
      (values (.. (vim.trim (pick-values 1 (string.gsub first-line "\\$" ""))) " …") true)
      (values first-line false))))

(fn tool-line [s tool]
  (let [(title cut?) (short-title s tool.title)
        (added removed) (render.diff-stats tool.details)]
    ;; The expanded details show the full title when the line had to shorten it.
    (set tool.full-title (when cut? tool.title))
    (.. "> tool: " title
        (if added (.. " (+" added " -" removed ")") "")
        " — " (or (. status-names tool.status) tool.status "pending"))))

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

(local thought-prefix ">> ")

(fn separator [prev]
  ;; What a new reply or thinking block needs in front of it so markdown keeps them
  ;; apart: a quoted line already leaves an empty line after it, otherwise add a blank line.
  (if (not prev) ""
      (= prev.type :line) "\n"
      (and (= prev.type :text) (vim.endswith prev.text "\n")) "\n"
      "\n\n"))

(fn add-stream [s kind text]
  ;; kind is :text (the reply) or :thought. Thinking is quoted with ">> " on every
  ;; line, which keeps it out of the reply and lets the chat window fold it.
  (let [turn s.turn
        prev (last-block turn)
        body (if (= kind :thought)
               (pick-values 1 (string.gsub text "\n" (.. "\n" thought-prefix)))
               text)
        text (if (and prev (= prev.type kind))
               body
               (.. (separator prev) (if (= kind :thought) thought-prefix "") body))]
    (if (and prev (= prev.type kind))
      (set prev.text (.. prev.text text))
      (table.insert turn.blocks {:type kind : text}))
    (render.append-text s text)))

(fn add-text [s text]
  (when (running? s) (busy s "writing"))
  (add-stream s :text text))

(fn add-thought [s text]
  (when (running? s) (busy s "thinking"))
  (add-stream s :thought text))

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
        (set label (.. "running " (short-title s tool.title activity-width))))))
  label)

(fn running-tools [s]
  ;; Tool calls still open in the running turn, oldest first.
  (if (not (running? s))
    []
    (icollect [_ id (ipairs (or s.turn.tool-ids []))]
      (let [tool (. s.tools id)]
        (when (and tool (or (= tool.status :pending) (= tool.status :in_progress)))
          tool)))))

(fn background-count [s]
  ;; Tool calls still running besides the one the activity label names: work the agent
  ;; has moved past, which is what a sub-agent left running in the background looks
  ;; like over ACP.
  (math.max 0 (- (length (running-tools s)) 1)))

(fn on-tool [s u]
  (if (not u.id)
    ;; A tool call with no id can't be updated or matched, so it would be invisible.
    (render.status s "ignored a tool call with no id")
    (let [tool {:id u.id :title u.title :kind u.kind :status u.status
                :updated (os.time) :details (or u.details {})}
          block {:type :line}]
      (set block.line (tool-line s tool))
      (set tool.block block)
      (tset s.tools u.id tool)
      (set s.last-tool-id u.id)
      (when (turn-active? s)
        (table.insert s.turn.tool-ids u.id)
        (add-line-block s block))
      (when (and (running? s) (or (= tool.status :pending) (= tool.status :in_progress)))
        (busy s (.. "running " (short-title s tool.title activity-width)))))))

(fn on-tool-update [s u]
  (let [tool (. s.tools u.id)]
    (if (not tool)
      (on-tool s (vim.tbl_extend :force u {:status (or u.status :pending)}))
      (do
        (when u.title (set tool.title u.title))
        (when u.kind (set tool.kind u.kind))
        (when u.status (set tool.status u.status))
        (each [k v (pairs (or u.details {}))]
          (tset tool.details k v))
        ;; It reported again: a later quiet spell is worth a fresh note.
        (set tool.updated (os.time))
        (set tool.stall-noted false)
        (set tool.block.line (tool-line s tool))
        (render.update-line s tool.block)
        (render.refresh-tool s tool)))
    (when (or (= u.status :completed) (= u.status :failed))
      (when (running? s) (busy s (still-running-label s)))
      (when (not s.replay)
        (pcall vim.cmd "checktime")))))

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
  (vim.fn.expand (or vim.g.acp-config-cache (.. (vim.fn.stdpath :data) "/acp-config.json"))))

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

;; Replay ------------------------------------------------------------------------------
;; session/load streams the old conversation back as updates. Your prompts open turns
;; and the rest fills them, much as live ones do, so the chat looks as it did.

(fn open-replay-turn [s]
  (when (not (turn-active? s))
    (let [turn {:state :replaying
                :prompt (or s.replay.prompt "")
                :blocks []
                :tool-ids []}]
      (set s.replay.prompt nil)
      (set s.turn turn)
      (render.begin-turn s turn))))

(fn close-replay-turn [s]
  (when (turn-active? s)
    (table.insert s.replay.turns s.turn)
    (set s.turn {:state :idle})))

(fn replay-update [s u]
  (if (= u.type :user)
    (do
      ;; Prompt text arrives in chunks; a reply already under way means this is the next one.
      (close-replay-turn s)
      (set s.replay.prompt (.. (or s.replay.prompt "") u.text)))
    (vim.tbl_contains [:text :thought :tool :tool-update] u.type)
    (open-replay-turn s)))

(fn abandon-replay [s]
  (when s.replay
    (when s.replay.prompt (open-replay-turn s))
    (close-replay-turn s)
    (set s.replay nil)))

(fn finish-replay [s]
  ;; Returns the replayed turns.
  (let [r s.replay]
    (abandon-replay s)
    r.turns))

(fn log-replayed [s turns]
  ;; A session already logged carries on in its file; one from elsewhere gets the
  ;; replayed turns written to a new one, so the log still holds the whole conversation.
  (if (log.adopt s)
    (log.append-note s "> acp: resumed")
    (do
      (set s.log.resumed true)
      (each [_ turn (ipairs turns)]
        (log.append-turn s turn)))))

(fn on-update [s params]
  ;; Nothing here is dropped in silence: an update for another session, or of a kind
  ;; this client doesn't know, leaves a note the first time it is seen.
  (let [session-id (protocol.update-session-id params)
        key (or session-id "no id")]
    (if (not= session-id s.session.id)
      (when (not (. s.ignored-sessions key))
        (tset s.ignored-sessions key true)
        (note s (.. "> acp: ignored updates for session " key)))
      (let [u (protocol.parse-update params)]
        (when u
          (set s.last-event (os.time))
          (when (and s.replay u)
            (replay-update s u))
          (case u.type
            :text (when (turn-active? s) (add-text s u.text))
            :thought (when (turn-active? s)
                       (if u.text
                         (add-thought s u.text)
                         (when (running? s) (busy s "thinking"))))
            :tool (on-tool s u)
            :tool-update (on-tool-update s u)
            :config (apply-config s u.options (not s.replay))
            :usage (do
                     (set s.usage {:used u.used :size u.size :cost u.cost :currency u.currency})
                     (vim.cmd "redrawstatus!"))
            :unknown (when (not (. s.unknown-kinds u.kind))
                       (tset s.unknown-kinds u.kind true)
                       (note s (.. "> acp: ignored a '" u.kind
                                   "' update, which the client doesn't know")))))))))

;; Credits -----------------------------------------------------------------------------

(fn refresh-credits [s]
  ;; Asks the agent's credits command again. One run at a time; a refresh asked for
  ;; while one runs follows it, so the figure is never older than the last turn.
  (when (and s.agent.credits-cmd (credits.enabled?))
    (if s.credits-running
      (set s.credits-again true)
      (do
        (set s.credits-running true)
        (credits.fetch s.agent.credits-cmd s.session.cwd
          (fn [text]
            (set s.credits-running false)
            (when (not s.ended)
              ;; A failed run keeps the last figure rather than blanking it.
              (when text
                (set s.credits text)
                (vim.cmd "redrawstatus!"))
              (when s.credits-again
                (set s.credits-again false)
                (refresh-credits s)))))))))

;; Permissions -------------------------------------------------------------------

(fn answer-permission [s choice]
  (let [p s.permission]
    (when p
      (set s.permission nil)
      (render.detach-lines s p.block)
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
        tool (. s.tools (or p.tool-id ""))
        title (or p.title (?. tool :title) "use a tool")
        block {:type :line : title}]
    (when s.permission
      ;; Only one prompt at a time; an older unanswered one is cancelled.
      (answer-permission s nil))
    (when tool
      ;; The request often knows more than the tool line so far, e.g. the diff.
      (each [k v (pairs p.details)]
        (tset tool.details k v))
      (when p.title (set tool.title p.title))
      (set tool.block.line (tool-line s tool))
      (render.update-line s tool.block)
      (render.refresh-tool s tool))
    (set block.line (permission-line s block))
    (if (turn-active? s)
      (add-line-block s block)
      (render.add-line s block))
    (set s.permission {: id : block :options p.options :choice-offset 0})
    (if (= s.turn.state :cancelling)
      (answer-permission s nil)
      (let [(_ cut?) (short-title s title)
            (lines offset) (render.permission-lines s (if tool tool.details p.details)
                                                    (when cut? title)
                                                    (or p.kind (?. tool :kind))
                                                    p.options)]
        ;; What's being asked for, then the choices; <CR> on a choice answers.
        (set s.permission.choice-offset offset)
        (render.attach-lines s block lines)
        (when (running? s) (busy s "waiting for your permission"))
        (when (not (render.visible? s.buf))
          (vim.notify (.. "acp: agent wants to: " (pick-values 1 (short-title s title))
                          " (:Acp to choose, or :AcpAllow / :AcpReject)")))))))

(fn choice-at [s row]
  ;; The permission choice on chat row (1-based), if any.
  (let [p s.permission
        index (when (and p row) (render.attached-index s p.block row))
        choice (when index (- index p.choice-offset))]
    (when (and choice (> choice 0))
      (. p.options choice))))

(fn choose-at [s row]
  ;; Answers the open permission request with the choice on row. Returns false if
  ;; there isn't one there.
  (let [choice (choice-at s row)]
    (if choice
      (do (answer-permission s choice) true)
      false)))

(fn choose-kind [s kinds]
  ;; Answers with the first choice whose kind is in kinds, tried in order.
  (let [p (?. s :permission)
        choice (when p
                 (accumulate [found nil _ kind (ipairs kinds) &until found]
                   (accumulate [hit nil _ o (ipairs p.options) &until hit]
                     (when (= o.kind kind) o))))]
    (if (not p)
      (vim.notify "acp: nothing is waiting for permission" vim.log.levels.WARN)
      (not choice)
      (vim.notify (.. "acp: the agent offered no " (. kinds 1) " choice") vim.log.levels.WARN)
      (answer-permission s choice))))

;; Elicitations -------------------------------------------------------------------
;; elicitation/create, form mode: the agent asks a question whose answers go
;; back over the wire. Only form mode is advertised at initialize, so url mode
;; and unknown modes are refused as invalid params, and a schema with fields
;; the client can't show is declined with a note.

(fn value-text [v]
  ;; An answer as shown in the chat, on one line, cut like an activity label.
  (let [text (case (type v)
               :boolean (if v "yes" "no")
               :string (pick-values 1 (string.gsub v "\n" "\\n"))
               :table (table.concat (vim.tbl_map tostring v) ", ")
               _ (tostring v))]
    (if (> (vim.fn.strchars text) activity-width)
      (.. (vim.fn.strcharpart text 0 (- activity-width 1)) "…")
      text)))

(fn answers-text [fields content]
  ;; The accepted answers, in the fields' order: "strategy=aggressive, notes=…".
  (table.concat (icollect [_ f (ipairs fields)]
                  (let [v (?. content f.name)]
                    (when (not= v nil)
                      (.. f.name "=" (value-text v)))))
                ", "))

(fn elicitation-line [s block]
  (.. "> elicitation: " (short-title s block.title)
      " — " (or block.choice "awaiting answer, <CR> to answer, :AcpDecline to decline")))

(fn answer-elicitation [s action content]
  ;; action is :accept, :decline or :cancel; content carries the accepted answers.
  (let [e s.elicitation]
    (when e
      (set s.elicitation nil)
      (render.detach-lines s e.block)
      (set e.block.choice (case action
                            :accept (.. "answered: " (answers-text e.fields content))
                            :decline "declined"
                            _ "cancelled"))
      (set e.block.line (elicitation-line s e.block))
      (render.update-line s e.block)
      (when (running? s) (busy s (still-running-label s)))
      (rpc.respond s.rpc e.id
                   (case action
                     :accept (protocol.elicitation-accept content)
                     :decline (protocol.elicitation-declined)
                     _ (protocol.elicitation-cancelled))))))

(fn on-elicitation [s params id]
  (let [e (protocol.parse-elicitation params)
        unsupported (accumulate [found nil _ f (ipairs e.fields) &until found]
                      (when (= f.kind :unsupported) f.name))]
    (if (not= e.mode :form)
      (do
        (rpc.respond-error s.rpc id -32602 (.. "elicitation mode '" (tostring e.mode)
                                               "' was not advertised"))
        (note s (.. "> acp: the agent asked for a " (tostring e.mode)
                    "-mode interaction, which the client can't show")))
      unsupported
      (do
        (rpc.respond s.rpc id (protocol.elicitation-declined))
        (note s (.. "> acp: the agent asked about '" unsupported "', a field type "
                    "the client can't show — declined")))
      (do
        (when s.elicitation
          ;; Only one question at a time; an older unanswered one is cancelled.
          (answer-elicitation s :cancel))
        (let [block {:type :line
                     :title (or (. (vim.split e.message "\n" {:plain true}) 1) "a question")}]
          (set block.line (elicitation-line s block))
          (if (turn-active? s)
            (add-line-block s block)
            (render.add-line s block))
          (set s.elicitation {: id : block :fields e.fields})
          (if (= s.turn.state :cancelling)
            (answer-elicitation s :cancel)
            (do
              (render.attach-lines s block (render.elicitation-lines e.message e.fields))
              (when (turn-active? s)
                (busy s "waiting for your answer"))
              (when (not (render.visible? s.buf))
                (vim.notify (.. "acp: agent asks: "
                                (short-title s block.title activity-width)
                                " (<CR> on it in the chat, or :AcpAnswer)"))))))))))

(fn answer-open [s]
  ;; The form walk for the open elicitation (:AcpAnswer, or <CR> on its line).
  (let [e s.elicitation]
    (if (not e)
      (vim.notify "acp: nothing is waiting for an answer" vim.log.levels.WARN)
      (form.ask e.fields
        (fn [action content]
          ;; The question may have been cancelled or replaced meanwhile.
          (when (= s.elicitation e)
            (answer-elicitation s action content)))))))

(fn decline-open [s]
  (if s.elicitation
    (answer-elicitation s :decline)
    (vim.notify "acp: nothing is waiting for an answer" vim.log.levels.WARN)))

(fn elicitation-at [s row]
  ;; The open elicitation if row (1-based) is its line or its attached form.
  (let [e s.elicitation]
    (when (and e row (not= nil (render.attached-index s e.block row)))
      e)))

(fn first-elicitation-row [s]
  ;; 1-based row of the waiting elicitation's line, if any.
  (render.line-row s (?. s :elicitation :block)))

;; Requests from the agent ---------------------------------------------------------

(fn on-request [s method params id]
  (if (= method protocol.methods.request-permission)
    (on-permission s params id)
    (= method protocol.methods.elicitation)
    (on-elicitation s params id)
    (rpc.method-not-found s.rpc id method)))

(fn on-notification [s method params]
  (when (= method protocol.methods.session-update)
    (on-update s params)))

;; Stalls ---------------------------------------------------------------------------
;; A sub-agent that stops reporting leaves a tool call running for ever: no update
;; arrives, so the spinner keeps turning and the turn looks alive. After a while of
;; silence the activity label says how long, and the chat gets one note about it.
;; vim.g.acp-stall-seconds is how long that silence has to last (60 by default).

(fn duration [secs]
  ;; 45s, 2m, 1h 5m.
  (if (< secs 60) (.. secs "s")
      (< secs 3600) (.. (math.floor (/ secs 60)) "m")
      (let [mins (% (math.floor (/ secs 60)) 60)]
        (.. (math.floor (/ secs 3600)) "h" (if (> mins 0) (.. " " mins "m") "")))))

(fn stall-seconds []
  (let [n vim.g.acp-stall-seconds]
    (if (and (= (type n) :number) (> n 0)) n 60)))

(fn stalled-tool [s now limit]
  ;; The running tool that has gone longest without an update, when it has been quiet
  ;; long enough to matter: background work that stopped reporting shows up here even
  ;; while the agent carries on with something else.
  (accumulate [worst nil _ tool (ipairs (running-tools s))]
    (let [silence (- now (or tool.updated now))]
      (if (and (>= silence limit) (or (not worst) (> silence worst.silence)))
        {: tool : silence}
        worst))))

(fn stall-note [s what silence]
  (note s (.. "> acp: no update from " what " for " (duration silence)
              " — it may be waiting on something that never reports back"))
  (when (not (render.visible? s.buf))
    (vim.notify (.. "acp: no update from " what " for " (duration silence)))))

(fn check-stall [s]
  ;; A permission or a question already explains the pause, so neither counts.
  (when (and (running? s) (not s.permission) (not s.elicitation))
    (let [now (os.time)
          limit (stall-seconds)
          stalled (stalled-tool s now limit)
          open (running-tools s)
          silence (- now (or s.last-event now))
          thinking-stalled (and (= 0 (length open)) (>= silence limit))
          was s.stalled]
      (if stalled
        (do
          (busy s (.. "running " (short-title s stalled.tool.title activity-width)
                      " — no update for " (duration stalled.silence)))
          (when (not stalled.tool.stall-noted)
            (set stalled.tool.stall-noted true)
            (stall-note s (.. "'" (short-title s stalled.tool.title) "'") stalled.silence)))
        thinking-stalled
        (do
          (busy s (.. "thinking — no update for " (duration silence)))
          (when (not s.stall-noted)
            (set s.stall-noted true)
            (stall-note s "the agent" silence)))
        was
        (do
          ;; Updates are arriving again: back to the ordinary label.
          (set s.stall-noted false)
          (busy s (still-running-label s))))
      (set s.stalled (if (or stalled thinking-stalled) true nil)))))

(fn stop-stall-timer [s]
  (when s.stall-timer
    (s.stall-timer:stop)
    (s.stall-timer:close)
    (set s.stall-timer nil))
  (set s.stall-noted false)
  (set s.stalled nil))

(fn start-stall-timer [s]
  ;; One tick a second while a turn runs; checking is cheap and the label only redraws
  ;; when its text changes.
  (stop-stall-timer s)
  (set s.last-event (os.time))
  (set s.stall-timer (vim.uv.new_timer))
  (s.stall-timer:start 1000 1000 (vim.schedule_wrap #(check-stall s))))

(fn note-unfinished [s turn]
  ;; The turn is over but a tool call never reported back: say so, rather than leave it
  ;; looking like it is still running.
  (let [unfinished (icollect [_ id (ipairs (or turn.tool-ids []))]
                     (let [tool (. s.tools id)]
                       (when (and tool (or (= tool.status :pending)
                                           (= tool.status :in_progress)))
                         tool)))]
    (when (> (length unfinished) 0)
      (note s (.. "> acp: " (length unfinished) " tool call"
                  (if (> (length unfinished) 1) "s" "") " never finished: "
                  (table.concat (icollect [_ t (ipairs unfinished)]
                                  (short-title s t.title activity-width))
                                ", "))))))

;; Turns ---------------------------------------------------------------------------

(fn end-turn [s err result]
  (let [turn s.turn
        reason (if err
                 (.. "error: " (or err.message "unknown"))
                 (. (protocol.parse-prompt-result result) :stop-reason))]
    (stop-stall-timer s)
    (when s.permission (answer-permission s nil))
    (when s.elicitation (answer-elicitation s :cancel))
    (note-unfinished s turn)
    (add-line-block s {:type :line :line (.. "> stop: " reason)})
    (set s.turn {:state :idle})
    (idle s)
    (refresh-credits s)
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
      (start-stall-timer s)
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
      (stop-stall-timer s)
      (rpc.notify s.rpc protocol.methods.session-cancel (protocol.cancel-params s.session.id))
      (answer-permission s nil)
      (answer-elicitation s :cancel)
      (busy s "cancelling"))
    (vim.notify "acp: nothing to cancel")))

;; Lifecycle -------------------------------------------------------------------------

(fn on-exit [s code]
  (set s.exited true)
  (stop-stall-timer s)
  (sandbox.stop s.sandbox)
  (when (and (not s.ended) (= vim.v.exiting vim.NIL))
    (rpc.fail-all s.rpc (.. "agent exited with code " code))
    (abandon-replay s)
    (set s.permission nil)
    (set s.elicitation nil)
    (set s.turn {:state :idle})
    (idle s)
    (render.status s (.. "agent exited with code " code
                         " — see " (transport.debug-path)))))

;; Resuming ------------------------------------------------------------------------

(fn resume-problem [info]
  ;; nil if the agent can list and load sessions, else why not.
  (let [name (or info.name "this agent")]
    (if (not info.load-session)
      (.. name " can't load earlier sessions")
      (not info.list-sessions)
      (.. name " can't list earlier sessions"))))

(fn list-sessions [s cwd done]
  ;; Every session the agent lists for cwd (all of them for nil), across its pages.
  ;; done is called with the sessions, or with nil and the error message.
  (let [all []]
    (fn page [cursor pages]
      (rpc.request s.rpc protocol.methods.session-list (protocol.list-params cwd cursor)
        (fn [err result]
          (if err
            (done nil (or err.message "unknown error"))
            (let [parsed (protocol.parse-list result)]
              (vim.list_extend all parsed.sessions)
              (if (and parsed.next-cursor (< pages 20))
                (page parsed.next-cursor (+ pages 1))
                (done all)))))))
    (page nil 1)))

(fn pick-live [s intent done]
  ;; Chooses an earlier session through a running session's agent, and calls done
  ;; with it. Nothing happens to the running session.
  (let [problem (resume-problem s.agent.info)]
    (if problem
      (vim.notify (.. "acp: " problem) vim.log.levels.WARN)
      (list-sessions s (when (not intent.all?)
                         ;; From the chat itself the project is the session's, not
                         ;; whatever root the chat buffer would have.
                         (if (= (vim.api.nvim_get_current_buf) s.buf)
                           s.session.cwd
                           (project-root)))
        (fn [sessions err]
          (if err
            (vim.notify (.. "acp: could not list sessions: " err) vim.log.levels.WARN)
            (history.select sessions intent
              (fn [chosen reason]
                (if chosen
                  (done chosen)
                  (vim.notify (.. "acp: " reason)))))))))))

(fn connected [s info requested resumed?]
  ;; The session exists: apply the requested settings, then take prompts.
  (when (next requested)
    (busy s "applying settings"))
  (configure s requested
    {:quiet true
     :done (fn []
             (set s.ready true)
             (idle s)
             (refresh-credits s)
             (render.status s (.. (if resumed?
                                    (.. "resumed " (or s.session.title s.session.id))
                                    (.. "connected to " (or info.name (. s.agent.cmd 1))))
                                  " · protocol v" (tostring info.protocol-version)
                                  " · " s.session.cwd))
             (when (> (length s.config) 0)
               (render.status s (config-summary s))))}))

(fn create-session [s info]
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
          (connected s info s.requested false))))))

(fn load-session [s info chosen]
  ;; chosen: {:id :cwd :title}. Settings stay as the session had them.
  (let [problem (resume-problem info)]
    (if problem
      (do (idle s) (render.status s problem))
      (do
        ;; Updates are matched on the id, and the replay starts before the reply to the load.
        (set s.session.id chosen.id)
        (set s.session.title (when chosen.title
                               (vim.trim (. (vim.split chosen.title "\n" {:plain true}) 1))))
        (when (and chosen.cwd (not= chosen.cwd s.session.cwd))
          (set s.session.cwd chosen.cwd)
          (set s.session.project (vim.fn.fnamemodify chosen.cwd ":t"))
          (render.retitle s))
        (set s.replay {:turns []})
        (busy s "loading session")
        (rpc.request s.rpc protocol.methods.session-load
                     (protocol.load-params chosen.id s.session.cwd)
          (fn [err result]
            (if err
              (do
                (abandon-replay s)
                (idle s)
                (render.status s (.. "session/load failed: " (or err.message "unknown"))))
              (let [turns (finish-replay s)
                    (ok e) (pcall log-replayed s turns)]
                (when (not ok)
                  (vim.notify (.. "acp: could not write session log: " (tostring e))
                              vim.log.levels.ERROR))
                (apply-config s (. (protocol.parse-load-session result) :config) false)
                (connected s info {} true)))))))))

(fn pick-session [s info]
  ;; The agent was started just to pick a session: list, choose, load into it. When
  ;; there's nothing to resume it carries on as a new session instead.
  (let [intent s.intent
        problem (resume-problem info)
        fall-back (fn [reason]
                    (render.status s (.. reason ", starting a new session"))
                    (create-session s info))]
    (if problem
      (fall-back problem)
      (do
        (busy s "listing sessions")
        (list-sessions s (when (not intent.all?) s.session.cwd)
          (fn [sessions err]
            (idle s)
            (if err
              (fall-back (.. "could not list sessions: " err))
              (history.select sessions intent
                (fn [chosen reason]
                  (if chosen
                    (load-session s info chosen)
                    (fall-back reason)))))))))))

(fn handshake [s]
  (rpc.request s.rpc protocol.methods.initialize (protocol.initialize-params)
    (fn [err result]
      (if err
        (do
          (idle s)
          (render.status s (.. "initialize failed: " (or err.message "unknown"))))
        (let [info (protocol.parse-initialize result)]
          (set s.agent.info info)
          (case s.intent.kind
            :load (load-session s info s.intent)
            :pick (pick-session s info)
            _ (create-session s info)))))))

(fn egress-line [s entry]
  ;; The proxy logs every attempt; a denied one is worth saying out loud, but only
  ;; once per host, or an agent retrying would bury the transcript.
  (when (and (= entry.kind "DENY") entry.host (not (. s.egress entry.host)))
    (tset s.egress entry.host true)
    (render.status s (.. "egress blocked: " entry.host))
    (log.append-note s (.. "> acp: egress blocked: " entry.host))))

(fn start [agent requested intent]
  ;; agent: a profile from modules.acp.agents.
  ;; requested: {setting value} applied once the session exists, before it takes prompts.
  ;; intent: {:kind :new} (the default), {:kind :pick :all? :id} to choose an earlier session
  ;; once the agent is up, or {:kind :load :id :cwd :title} for one already chosen.
  (let [intent (or intent {:kind :new})
        cwd (or intent.cwd (project-root))
        s {:agent {:name agent.name :cmd agent.cmd :credits-cmd agent.credits-cmd
                   :sandbox agent.sandbox}
           : intent
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
           :credits nil
           :permission nil
           :elicitation nil
           :ignored-sessions {}
           :unknown-kinds {}
           :last-event (os.time)
           :egress {}}]
    (log.init s)
    (render.create-buffers s)
    (set s.rpc (rpc.new {:send (fn [line] (transport.send s.agent.proc line))
                         :on-request (fn [method params id] (on-request s method params id))
                         :on-notification (fn [method params] (on-notification s method params))}))
    (let [(box problem) (sandbox.prepare agent.sandbox cwd)]
      (if problem
        (do
          (set sessions.current s)
          (set s.exited true)
          (render.status s (.. "could not start agent: " problem)))
        (let [(proc err) (transport.start s.agent.cmd cwd
                                          {:on-line (fn [line] (rpc.receive s.rpc line))
                                           :on-exit (fn [code] (on-exit s code))}
                                          agent.env-remove box)]
          (set s.agent.proc proc)
          (set s.sandbox box)
          (set sessions.current s)
          (if proc
            (do
              (render.status s (.. "starting " (table.concat s.agent.cmd " ") "…"))
              (when box
                (render.status s (.. "sandbox: " (sandbox.describe agent.sandbox)))
                (sandbox.watch box (fn [entry] (egress-line s entry))))
              (busy s "starting agent")
              (handshake s))
            (do
              (sandbox.stop box)
              (set s.exited true)
              (render.status s (.. "could not start agent: " (tostring err))))))))
    s))

(fn stop [s]
  (when s
    (when (= s.turn.state :running) (cancel s))
    (set s.ended true)
    (stop-stall-timer s)
    (when (and s.agent.proc (not s.exited))
      (transport.stop s.agent.proc (and s.sandbox true)))
    (sandbox.stop s.sandbox)
    (render.wipe s)
    (when (= sessions.current s)
      (set sessions.current nil))
    (if s.log.path
      (vim.notify (.. "acp: session log " s.log.path))
      (vim.notify "acp: session ended"))))

(fn current []
  sessions.current)

(fn shutdown []
  ;; Neovim is exiting: stop the agent without touching buffers or notifying.
  (let [s sessions.current]
    (when s
      (set s.ended true)
      (stop-stall-timer s)
      (render.activity s nil)
      (when (and s.agent.proc (not s.exited))
        (transport.stop s.agent.proc (and s.sandbox true)))
      (sandbox.stop s.sandbox))))

(fn session-buffer? [s buf]
  (= buf s.buf))

(fn first-choice-row [s]
  ;; 1-based row of the first choice of a waiting permission request, if any.
  (let [row (when s.permission (render.line-row s s.permission.block))]
    (when row (+ row s.permission.choice-offset 1))))

(local status-groups
  {:frame "AcpStatus"
   :name "AcpStatusName"
   :agent "AcpStatusAgent"
   :model "AcpStatusModel"
   :mode "AcpStatusMode"
   :context "AcpStatusContext"
   :context-warn "AcpStatusContextWarn"
   :context-critical "AcpStatusContextCritical"
   :cost "AcpStatusCost"
   :credits "AcpStatusCredits"
   :sandbox "AcpStatusSandbox"
   :background "AcpStatusBackground"
   :separator "AcpStatusSeparator"
   :activity "AcpStatusActivity"
   :alert "AcpStatusAlert"})

(fn status-highlight [group text]
  ;; Statusline text in a highlight group, with % escaped so it survives the parser.
  (.. "%#" group "#"
      (pick-values 1 (string.gsub (tostring text) "%%" "%%%%"))
      "%#" status-groups.frame "#"))

(fn status-context-group [pct]
  (if (>= pct 90) status-groups.context-critical
      (>= pct 70) status-groups.context-warn
      status-groups.context))

(fn status-activity-group [s]
  (let [label (?. s :activity :label)
        asks? (and label (or (string.find label "permission" 1 true)
                             (string.find label "answer" 1 true)
                             (string.find label "no update" 1 true)))]
    (if asks?
      status-groups.alert
      status-groups.activity)))

(fn status-text []
  ;; Statusline segment. Agent, sandbox, model, mode, context use, session cost and
  ;; account credits show in the session's own windows; activity shows everywhere
  ;; while the agent is working, and the background count with it.
  (let [s sessions.current]
    (if (not s)
      ""
      (let [sep (status-highlight status-groups.separator " · ")
            details (when (session-buffer? s (vim.api.nvim_get_current_buf))
                      (let [parts []]
                        (table.insert parts (status-highlight status-groups.agent s.agent.name))
                        (let [model (config-by-category s :model)
                              mode (config-by-category s :mode)]
                          (when model
                            (table.insert parts (status-highlight status-groups.model model.display)))
                          (when mode
                            (table.insert parts (status-highlight status-groups.mode mode.display))))
                        (when (and s.usage s.usage.size (> s.usage.size 0))
                          (let [pct (math.floor (/ (* 100 s.usage.used) s.usage.size))]
                            (table.insert parts
                                          (status-highlight (status-context-group pct) (.. pct "%")))))
                        (when (= (type (?. s.usage :cost)) :number)
                          (let [cost (if (or (= s.usage.currency "USD") (not s.usage.currency))
                                         (string.format "$%.2f" s.usage.cost)
                                         (string.format "%.2f %s" s.usage.cost s.usage.currency))]
                            (table.insert parts (status-highlight status-groups.cost cost))))
                        (when s.credits
                          (table.insert parts (status-highlight status-groups.credits s.credits)))
                        ;; Last of the details, so a narrow window clips the model first.
                        (when s.sandbox
                          (table.insert parts (status-highlight status-groups.sandbox "sandbox")))
                        (when (> (length parts) 0)
                          (table.concat parts sep))))
            activity (render.activity-text s)
            background (background-count s)
            body (let [parts []
                       add (fn [part separator]
                             (when part
                               (when (> (length parts) 0)
                                 (table.insert parts
                                               (status-highlight status-groups.separator separator)))
                               (table.insert parts part)))]
                   (add details " · ")
                   (when activity
                     (add (status-highlight (status-activity-group s) activity) " | "))
                   (add (when (> background 0)
                          (status-highlight status-groups.background (.. background " bg")))
                        " · ")
                   (table.concat parts ""))]
        (if (> (length body) 0)
          (.. (status-highlight status-groups.frame "[")
              (status-highlight status-groups.name "acp") " "
              body
              (status-highlight status-groups.frame "]")
              "%*")
          "")))))

(fn config [s]
  (or (?. s :config) []))

(fn tool-at [s row]
  ;; The tool call whose summary line, or inline expansion, covers row (1-based).
  (when (and s row)
    (accumulate [found nil _ tool (pairs s.tools) &until found]
      (when (render.expansion-contains? s tool row) tool))))

(fn toggle-tool [s row]
  ;; Expands or collapses the tool call at row. Returns false if there isn't one.
  (let [tool (tool-at s row)]
    (if (not tool)
      false
      (do
        (if (render.expanded? tool)
          (render.collapse-tool s tool)
          (render.expand-tool s tool))
        true))))

(fn show-latest-tool [s mods]
  (let [tool (when s (. s.tools (or s.last-tool-id "")))]
    (if tool
      (render.open-tool-details s tool (or (. status-names tool.status) tool.status "pending") mods)
      (vim.notify "acp: no tool calls in this session" vim.log.levels.WARN))))

{: start
 : project-root
 : list-sessions
 : pick-live
 : shutdown
 : status-text
 : config
 : config-option
 : tool-at
 : choice-at
 : choose-at
 : first-choice-row
 : first-elicitation-row
 : choose-kind
 : answer-open
 : decline-open
 : elicitation-at
 : toggle-tool
 : show-latest-tool
 : known-config
 : validate
 : set-config
 : configure
 : stop
 : send-prompt
 : cancel
 : current
 : alive?}
