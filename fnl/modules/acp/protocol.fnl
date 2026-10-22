;; Every ACP version-specific shape lives here (protocol version 1).

(local version 1)

(local methods
  {:initialize "initialize"
   :authenticate "authenticate"
   :session-new "session/new"
   :session-prompt "session/prompt"
   :session-cancel "session/cancel"
   :session-update "session/update"
   :set-config-option "session/set_config_option"
   :request-permission "session/request_permission"})

(fn initialize-params []
  {:protocolVersion version
   :clientCapabilities {:fs {:readTextFile false :writeTextFile false}
                        :terminal false}
   :clientInfo {:name "nvim-acp" :title "Neovim ACP client" :version "0.1.0"}})

(fn parse-initialize [result]
  (let [caps (or result.agentCapabilities {})
        info (or result.agentInfo {})]
    {:protocol-version result.protocolVersion
     :load-session (= caps.loadSession true)
     :auth-methods (icollect [_ m (ipairs (or result.authMethods []))]
                     (or m.name m.id))
     :name (or info.title info.name)
     :version info.version}))

(fn new-session-params [cwd]
  {: cwd :mcpServers []})

(fn parse-config-options [options]
  ;; Select options only (boolean ones need a client capability we don't declare).
  ;; Grouped values are flattened, keeping the agent's order.
  (icollect [_ o (ipairs (or options []))]
    (when (= o.type :select)
      (let [choices []]
        (each [_ v (ipairs (or o.options []))]
          (if v.group
            (each [_ gv (ipairs (or v.options []))]
              (table.insert choices {:value gv.value :name gv.name :description gv.description}))
            (table.insert choices {:value v.value :name v.name :description v.description})))
        {:id o.id
         :name o.name
         :category o.category
         :current o.currentValue
         :values choices}))))

(fn parse-new-session [result]
  {:id result.sessionId
   :config (parse-config-options result.configOptions)})

(fn set-config-params [session-id config-id value]
  {:sessionId session-id :configId config-id : value})

(fn parse-set-config-result [result]
  (parse-config-options (?. result :configOptions)))

(fn prompt-params [session-id text]
  {:sessionId session-id
   :prompt [{:type :text : text}]})

(fn parse-prompt-result [result]
  {:stop-reason (or (?. result :stopReason) "unknown")})

(fn cancel-params [session-id]
  {:sessionId session-id})

(fn content-text [content]
  (when (and content (= content.type :text))
    content.text))

(fn parse-update [params]
  ;; Normalises a session/update into {:type ...}, or nil for kinds v1 ignores.
  (let [u (or params.update {})]
    (case u.sessionUpdate
      :agent_message_chunk
      (let [text (content-text u.content)]
        (when text {:type :text : text}))
      :agent_thought_chunk
      {:type :thought}
      :config_option_update
      {:type :config :options (parse-config-options u.configOptions)}
      :usage_update
      {:type :usage :used u.used :size u.size}
      :tool_call
      {:type :tool
       :id u.toolCallId
       :title u.title
       :kind u.kind
       :status (or u.status :pending)}
      :tool_call_update
      {:type :tool-update
       :id u.toolCallId
       :title u.title
       :kind u.kind
       :status u.status}
      _ nil)))

(fn update-session-id [params]
  params.sessionId)

(fn parse-permission [params]
  (let [tool (or params.toolCall {})]
    {:session-id params.sessionId
     :tool-id tool.toolCallId
     :title tool.title
     :options (icollect [_ o (ipairs (or params.options []))]
                {:id o.optionId :name o.name :kind o.kind})}))

(fn permission-selected [option-id]
  {:outcome {:outcome :selected :optionId option-id}})

(fn permission-cancelled []
  {:outcome {:outcome :cancelled}})

{: version
 : methods
 : initialize-params
 : parse-initialize
 : new-session-params
 : parse-new-session
 : set-config-params
 : parse-set-config-result
 : prompt-params
 : parse-prompt-result
 : cancel-params
 : parse-update
 : update-session-id
 : parse-permission
 : permission-selected
 : permission-cancelled}
