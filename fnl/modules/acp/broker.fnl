;; Delegation: lets a session's agent start and track agents from other providers.
;;
;; ACP gives an agent no way to ask its client for another agent, so the session is
;; handed MCP tools instead, answered here. A child is an ordinary session with its own
;; process, sandbox, chat and log, started in the parent's project.
;;
;; A profile opts in with :delegate, see modules.acp.agents. The limits are deliberate:
;;   - Children get no tools of their own, so delegation goes one level down.
;;   - A sandboxed parent only starts sandboxed children. A child with no policy of its
;;     own gets a sandbox with no host allowed.
;;   - No tool answers a child's permission, question or egress prompt. Those wait in
;;     the child's chat for you, or an agent could approve its own actions through
;;     another agent.
;;   - agent_start takes a model but not a mode, as a mode can turn off those prompts.
;; vim.g.acp-delegate-max is how many children may run at once (4 by default).
;;
;; The same server gives every session behind the egress proxy the egress_status tool,
;; :delegate or not: a request held for your answer looks like an unrelated failure to
;; the agent, so this is how it finds out, and waits instead of guessing. It only reads:
;; the answer stays yours, over the proxy's stdin. vim.g.acp-egress-wait-seconds is how
;; long a host can wait on you before the tool says to stop waiting (300 by default).

(local agents (require :modules.acp.agents))
(local mcp (require :modules.acp.mcp))
(local protocol (require :modules.acp.protocol))
(local sandbox (require :modules.acp.sandbox))
(local session (require :modules.acp.session))

(local reply-limit 30000)
(local tool-limit 100)
(local wait-default 30)
;; Under the stall note's 60 seconds, so a poll doesn't look like a stuck tool.
(local wait-limit 55)
(local poll-ms 250)

(fn max-children []
  (let [n vim.g.acp-delegate-max]
    (if (and (= (type n) :number) (> n 0)) n 4)))

(fn allowed [delegate]
  ;; The agents a :delegate setting names: true is all of them.
  (if (= delegate true)
    (agents.names)
    (= (type delegate) :table)
    (icollect [_ name (ipairs delegate)]
      (when (agents.get name) name))
    []))

;; What a tool returns --------------------------------------------------------------

(fn model-name [s]
  (accumulate [found nil _ o (ipairs (session.config s)) &until found]
    (when (= o.category :model) o.display)))

(fn status [child]
  (let [s child.session]
    {:id child.id
     :agent s.agent.name
     :state (session.state s)
     :title s.session.title
     :model (model-name s)
     :activity (?. s :activity :label)
     :waiting_for_user (session.waiting-for s)
     :running_tools (icollect [_ tool (ipairs (session.running-tools s))]
                      tool.title)
     :turns_finished (or s.turns-finished 0)
     :stop_reason (?. s :last-turn :stop-reason)
     :error s.failed
     :log s.log.path}))

(fn shorten-reply [text]
  (if (> (length text) reply-limit)
    (.. (string.sub text 1 reply-limit)
        "\n\n[cut at " reply-limit " bytes, the whole reply is in the session log]")
    text))

(fn result [child]
  (let [turn child.session.last-turn]
    (vim.tbl_extend :force (status child)
                    (if turn
                      {:reply (shorten-reply turn.reply)
                       :tools (vim.list_slice turn.tools 1 tool-limit)}
                      {}))))

;; Tools ----------------------------------------------------------------------------

(fn child-by-id [b id]
  (accumulate [found nil _ child (ipairs b.children) &until found]
    (when (= child.id id) child)))

(fn with-child [b args fail f]
  (let [child (child-by-id b args.id)]
    (if child
      (f child)
      (fail (.. "no agent with id " (tostring args.id) ", agent_list shows them")))))

(fn busy? [s]
  (vim.tbl_contains [:starting :running :waiting_for_user] (session.state s)))

(fn running-count [b]
  (accumulate [n 0 _ child (ipairs b.children)]
    (if (busy? child.session) (+ n 1) n)))

(fn child-sandbox [profile parent]
  (if (and parent.sandbox (not profile.sandbox))
    true
    profile.sandbox))

(fn start-child [b args done fail]
  (let [name args.agent
        prompt args.prompt
        parent b.parent]
    (if (not (vim.tbl_contains b.allowed name))
      (fail (.. "agent " (tostring name) " can't be started from here, it can be one of: "
                (table.concat b.allowed ", ")))
      (or (not= (type prompt) :string) (= (vim.trim prompt) ""))
      (fail "a prompt is needed")
      (>= (running-count b) (max-children))
      (fail (.. (max-children) " agents are already running, wait for one or stop it"))
      (let [profile (agents.get name)
            _ (set b.started (+ b.started 1))
            id (.. name "-" b.started)
            _ (set profile.sandbox (child-sandbox profile parent))
            child {: id}]
        (table.insert b.children child)
        (set child.session
             (session.start profile
                            (if (= (type args.model) :string) {:model args.model} {})
                            {:kind :new :cwd parent.session.cwd}
                            {: parent
                             :label id
                             :on-ready (fn [s] (session.send-prompt s prompt))}))
        (b.on-child child.session)
        (session.note parent (.. "> acp: started " id " (:AcpAgents to watch it)"))
        (done (status child))))))

(fn hold [b args settled? finish]
  ;; Holds a call until settled? or the time is up, then (finish timed-out?). An MCP
  ;; client gives up on a call that takes too long, so this one ends in good time and
  ;; says it can be asked again.
  (let [seconds (math.min wait-limit (math.max 1 (or (tonumber args.timeout) wait-default)))
        deadline (+ (vim.uv.now) (* seconds 1000))
        timer (vim.uv.new_timer)
        end (fn [timed-out?]
              (timer:stop)
              (timer:close)
              (finish timed-out?))]
    (if (settled?)
      (do (timer:close)
          (finish false))
      (timer:start poll-ms poll-ms
                   (vim.schedule_wrap
                     (fn []
                       (when (not (timer:is_closing))
                         (if (or (settled?) b.closed)
                           (end false)
                           (>= (vim.uv.now) deadline)
                           (end true)))))))))

(fn wait-for [b child args done]
  ;; Until the agent stops working or needs you.
  (hold b args
        #(vim.tbl_contains [:idle :waiting_for_user :failed :exited :stopped]
                           (session.state child.session))
        #(done (vim.tbl_extend :force (result child) {:timed_out $1}))))

(fn send-to-child [child args done fail]
  (let [s child.session
        state (session.state s)]
    (if (or (not= (type args.prompt) :string) (= (vim.trim args.prompt) ""))
      (fail "a prompt is needed")
      (not= state :idle)
      (fail (.. child.id " is " state ", it takes a prompt when idle"))
      (do
        (session.send-prompt s args.prompt)
        (done (status child))))))

(fn cancel-child [child done]
  (when (= (. child.session.turn :state) :running)
    (session.cancel child.session))
  (done (status child)))

(fn stop-child [child done]
  (when (not child.session.ended)
    (session.stop child.session))
  (done (status child)))

(fn schema [properties required]
  {:type :object :properties properties :required (or required [])})

(local id-property {:type :string :description "The id agent_start returned."})

(fn agent-tools [b]
  [{:name "agent_list"
    :description "List the agents that can be started, and the ones started so far."
    :inputSchema (schema (vim.empty_dict))
    :run (fn [_ done]
           (done {:available b.allowed
                  :started (icollect [_ child (ipairs b.children)] (status child))}))}
   {:name "agent_start"
    :description (.. "Start another agent in this project on a task, and return at once with its "
                     "id. It runs in its own session with none of this conversation, so the prompt "
                     "must stand alone. Its permission requests go to the user, not to you. Follow "
                     "it with agent_wait.")
    :inputSchema (schema {:agent {:type :string :description "Which agent, from agent_list."}
                          :prompt {:type :string :description "The task."}
                          :model {:type :string :description "The model, if not its default."}}
                         ["agent" "prompt"])
    :run (fn [args done fail] (start-child b args done fail))}
   {:name "agent_status"
    :description "How a started agent is getting on, without waiting."
    :inputSchema (schema {:id id-property} ["id"])
    :run (fn [args done fail]
           (with-child b args fail #(done (status $1))))}
   {:name "agent_wait"
    :description (.. "Wait until an agent finishes its turn or needs the user, then return its "
                     "state and any reply. timed_out true means it is still working, so call this "
                     "again. A state of waiting_for_user means only the user can move it on: tell "
                     "them what it is waiting for.")
    :inputSchema (schema {:id id-property
                          :timeout {:type :number
                                    :description (.. "Seconds to wait, at most " wait-limit
                                                     ", " wait-default " by default.")}}
                         ["id"])
    :run (fn [args done fail]
           (with-child b args fail #(wait-for b $1 args done)))}
   {:name "agent_result"
    :description "The reply and tool calls of an agent's last finished turn."
    :inputSchema (schema {:id id-property} ["id"])
    :run (fn [args done fail]
           (with-child b args fail #(done (result $1))))}
   {:name "agent_send"
    :description "Send an idle agent a follow-up prompt, in the same session."
    :inputSchema (schema {:id id-property :prompt {:type :string}} ["id" "prompt"])
    :run (fn [args done fail]
           (with-child b args fail #(send-to-child $1 args done fail)))}
   {:name "agent_cancel"
    :description "Cancel an agent's running turn. Its session stays open."
    :inputSchema (schema {:id id-property} ["id"])
    :run (fn [args done fail]
           (with-child b args fail #(cancel-child $1 done)))}
   {:name "agent_stop"
    :description "End an agent's session and close its chat. Its log is kept."
    :inputSchema (schema {:id id-property} ["id"])
    :run (fn [args done fail]
           (with-child b args fail #(stop-child $1 done)))}])

;; Egress ---------------------------------------------------------------------------

(fn egress-wait-limit []
  (let [n vim.g.acp-egress-wait-seconds]
    (if (and (= (type n) :number) (> n 0)) n 300)))

(fn overdue? [entry]
  (>= entry.waited_seconds (egress-wait-limit)))

(local egress-advice
  {:allowed "The user allowed this host for the session. Retry the request."
   :denied (.. "The user refused this attempt. Don't look for another way to reach it: tell "
               "them what needed it. Trying again asks them again.")
   :blocked (.. "The user refused this host for the session. Don't look for another way to "
                "reach it: tell them what needed it.")
   :refused (.. "This host isn't on the sandbox's allowlist. Don't look for another way to "
                "reach it: tell the user, who can allow it.")})

(fn advice [entry]
  (if (not= entry.state :pending)
    (. egress-advice entry.state)
    (overdue? entry)
    (.. "The user hasn't answered. Stop waiting: tell them this host is blocking you, and "
        "finish what you can without it.")
    "The user hasn't answered yet. Call this again to keep waiting."))

(fn egress-status [b timed-out?]
  (let [hosts (icollect [_ entry (ipairs (session.egress-report b.parent))]
                (vim.tbl_extend :force entry {:next (advice entry)}))]
    {: hosts
     :timed_out timed-out?
     :note (when (= 0 (length hosts))
             "No host has been held or refused, so a network failure has some other cause.")}))

(fn egress-wait [b args done]
  ;; Until you answer about one of the hosts still worth waiting for. One you've been
  ;; asked about for too long doesn't hold the call, or nothing would end the wait.
  (let [waited-on (icollect [_ entry (ipairs (session.egress-pending b.parent))]
                    (when (not (overdue? entry)) entry.host))
        pending? (fn [host]
                   (accumulate [found false _ entry (ipairs (session.egress-pending b.parent))]
                     (or found (= entry.host host))))]
    (hold b args
          #(or (= 0 (length waited-on))
               (accumulate [answered false _ host (ipairs waited-on)]
                 (or answered (not (pending? host)))))
          #(done (egress-status b $1)))))

(fn egress-tools [b]
  [{:name "egress_status"
    :description (.. "Where this sandbox's network requests stand: each host held for the user's "
                     "answer or refused, with what to do next. Call it after any failure that "
                     "could be the network, as a held request can look like a timeout or an "
                     "unrelated error. While a host is pending this waits for the user's answer, "
                     "and timed_out true means they haven't answered yet. It can't approve "
                     "anything: only the user can.")
    :inputSchema (schema {:timeout {:type :number
                                    :description (.. "Seconds to wait for an answer, at most "
                                                     wait-limit ", " wait-default " by default.")}})
    :run (fn [args done] (egress-wait b args done))}])

(local egress-instructions
  (.. "This agent's network goes through a proxy that allows only listed hosts. A request to "
      "any other host is held while the user is asked, which often outlasts the client's own "
      "timeout, so it can look like a timeout or an unrelated error from whatever made it. "
      "After a failure that could be the network, call egress_status before drawing any "
      "conclusion about the cause. Only the user can approve a host: don't try to reach one "
      "another way."))

;; Lifecycle ------------------------------------------------------------------------

(fn close [b]
  (when (not b.closed)
    (set b.closed true)
    (each [_ child (ipairs b.children)]
      (when (and child.session (not child.session.ended))
        (session.stop child.session)))
    (mcp.stop b.server)))

(fn open [agent on-child]
  ;; The broker for a session of agent, or nil if it has no use for one, and anything
  ;; about :delegate worth saying. A sandboxed agent's port is forwarded and allowed up
  ;; front, so agent.sandbox changes here. Call before session.start.
  (let [names (allowed agent.delegate)
        net (?. (sandbox.normalize agent.sandbox) :net)
        delegates? (and (> (length names) 0) (not= net false))
        proxied? (= net :proxy)
        said (if (and agent.delegate (= 0 (length names)))
               "delegation is off: :delegate names no known agent"
               (and (> (length names) 0) (= net false))
               "delegation is off: this sandbox has no network to reach Neovim through")]
    (if (not (or delegates? proxied?))
      (values nil said)
      (let [b {:allowed names : on-child :children [] :started 0}
            listed (vim.list_extend (if delegates? (agent-tools b) [])
                                    (if proxied? (egress-tools b) []))
            (server problem) (mcp.start "nvim-acp" listed (when proxied? egress-instructions))]
        (if server
          (do
            (set b.server server)
            (set agent.sandbox (sandbox.forward agent.sandbox server.port))
            (values b said))
          (values nil (.. (if delegates? "delegation is off: " "egress_status is off: ") problem)))))))

(fn session-options [b]
  ;; What session.start needs for the parent.
  {:mcp-servers [(protocol.http-mcp-server b.server.name b.server.url b.server.token)]
   :on-stop #(close b)})

(fn attach [b parent]
  (set b.parent parent))

{: open
 : session-options
 : attach
 : close
 : allowed}
