;; Every ACP version-specific shape lives here (protocol version 1).

(local version 1)

(local methods
  {:initialize "initialize"
   :authenticate "authenticate"
   :session-new "session/new"
   :session-load "session/load"
   :session-list "session/list"
   :session-prompt "session/prompt"
   :session-cancel "session/cancel"
   :session-update "session/update"
   :set-config-option "session/set_config_option"
   :request-permission "session/request_permission"
   :elicitation "elicitation/create"
   :elicitation-complete "elicitation/complete"})

(fn initialize-params []
  {:protocolVersion version
   :clientCapabilities {:fs {:readTextFile false :writeTextFile false}
                        :terminal false
                               ;; Form mode only: url mode needs consent prompts of its own.
                               :elicitation {:form (vim.empty_dict)}}
   :clientInfo {:name "nvim-acp" :title "Neovim ACP client" :version "0.1.0"}})

(fn parse-initialize [result]
  (let [caps (or result.agentCapabilities {})
        info (or result.agentInfo {})]
    {:protocol-version result.protocolVersion
     :load-session (= caps.loadSession true)
     :list-sessions (not= nil (?. caps :sessionCapabilities :list))
     :auth-methods (icollect [_ m (ipairs (or result.authMethods []))]
                     (or m.name m.id))
     :name (or info.title info.name)
     :version info.version}))

(fn new-session-params [cwd]
  {: cwd :mcpServers []})

(fn load-params [session-id cwd]
  {:sessionId session-id : cwd :mcpServers []})

(fn list-params [cwd cursor]
  ;; Both optional: no cwd lists every project's sessions.
  (if (or cwd cursor)
    {: cwd : cursor}
    (vim.empty_dict)))

(fn parse-list [result]
  {:sessions (icollect [_ i (ipairs (or (?. result :sessions) []))]
               {:id i.sessionId :cwd i.cwd :title i.title :updated i.updatedAt})
   :next-cursor (?. result :nextCursor)})

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

(fn parse-load-session [result]
  {:config (parse-config-options (?. result :configOptions))})

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

(fn tool-details [u]
  ;; The parts of a tool call worth expanding. Each field is only present when the
  ;; update carries it; a field that's sent replaces the previous value.
  (let [details {}]
    (when u.content
      (set details.content
           (icollect [_ c (ipairs u.content)]
             (case c.type
               :diff {:type :diff :path c.path :old (or c.oldText "") :new (or c.newText "")}
               :content (let [text (content-text c.content)]
                          (when text {:type :text : text}))
               _ nil))))
    (when u.locations
      (set details.locations
           (icollect [_ l (ipairs u.locations)]
             {:path l.path :line l.line})))
    (when (not= u.rawInput nil) (set details.input u.rawInput))
    (when (not= u.rawOutput nil) (set details.output u.rawOutput))
    details))

(fn parse-update [params]
  ;; Normalises a session/update into {:type ...}. Kinds this client doesn't know come
  ;; back as :unknown rather than nil, so the session can say so instead of dropping
  ;; them: an agent's newer kinds are where sub-agent progress tends to hide.
  (let [u (or params.update {})]
    (case u.sessionUpdate
      :agent_message_chunk
      (let [text (content-text u.content)]
        (when text {:type :text : text}))
      :user_message_chunk
      (let [text (content-text u.content)]
        (when text {:type :user : text}))
      :agent_thought_chunk
      {:type :thought :text (content-text u.content)}
      :config_option_update
      {:type :config :options (parse-config-options u.configOptions)}
      :usage_update
      {:type :usage :used u.used :size u.size
       :cost (?. u :cost :amount) :currency (?. u :cost :currency)}
      :tool_call
      {:type :tool
       :id u.toolCallId
       :title u.title
       :kind u.kind
       :status (or u.status :pending)
       :details (tool-details u)}
      :tool_call_update
      {:type :tool-update
       :id u.toolCallId
       :title u.title
       :kind u.kind
       :status u.status
       :details (tool-details u)}
      _ (when u.sessionUpdate
          {:type :unknown :kind (tostring u.sessionUpdate)}))))

(fn update-session-id [params]
  params.sessionId)

(fn parse-permission [params]
  (let [tool (or params.toolCall {})]
    {:session-id params.sessionId
     :tool-id tool.toolCallId
     :title tool.title
     :kind tool.kind
     :details (tool-details tool)
     :options (icollect [_ o (ipairs (or params.options []))]
                {:id o.optionId :name o.name :kind o.kind})}))

(fn permission-selected [option-id]
  {:outcome {:outcome :selected :optionId option-id}})

(fn permission-cancelled []
  {:outcome {:outcome :cancelled}})

(fn choice-values [enum]
  ;; The options come as enum or oneOf. Entries may be plain values or
  ;; {const, name or title, description} objects.
  (icollect [_ v (ipairs (or enum []))]
    (if (and (= (type v) :table) v.const)
      {:value v.const :name (or v.name v.title (tostring v.const)) :description v.description}
      {:value v :name (tostring v)})))

(fn field-kind [p]
  ;; The kinds of answer the client can ask for; anything else is declined.
  (case p.type
    :boolean :boolean
    :number :number
    :integer :number
    :string (if (or p.enum p.oneOf) :choice :string)
    ;; A multi-select: an array whose items are drawn from a fixed set.
    :array (if (and (= (type p.items) :table) (or p.items.enum p.items.anyOf p.items.oneOf))
             :multichoice
             :unsupported)
    _ :unsupported))

(fn parse-field [name p]
  ;; One property of a form-mode schema: flat, primitive types only.
  (let [field {:name name
               :kind (field-kind p)
               :required? false
               :title p.title
               :description p.description
               :default (?. p :default)}]
    (case field.kind
      :choice (set field.values (choice-values (or p.oneOf p.enum)))
      :multichoice (do (set field.values (choice-values (or p.items.anyOf p.items.oneOf p.items.enum)))
                       (set field.min-items p.minItems)
                       (set field.max-items p.maxItems))
      :number (do (set field.minimum p.minimum)
                  (set field.maximum p.maximum))
      _ nil)
    field))

(fn parse-elicitation [params]
  ;; Form mode only. Every mode is parsed as-is so the caller can reject the
  ;; ones it never advertised; url mode carries no schema at all.
  (let [schema (or params.requestedSchema {})
        fields (icollect [name p (pairs (or schema.properties {}))]
                 (parse-field name p))]
    (each [_ f (ipairs fields)]
      (set f.required? (vim.tbl_contains (or schema.required []) f.name)))
    ;; Fields arrive as a JSON object with no order of its own: required first,
    ;; then by name, so the walk always asks the same way.
    (table.sort fields (fn [a b]
                         (if (not= a.required? b.required?)
                           a.required?
                           (< a.name b.name))))
    {:mode (or params.mode :form)
     :message (or params.message "")
     :session-id params.sessionId
     :tool-call-id params.toolCallId
     :elicitation-id params.elicitationId
     :fields fields}))

(fn elicitation-accept [content]
  {:action "accept" :content content})

(fn elicitation-declined []
  {:action "decline"})

(fn elicitation-cancelled []
  {:action "cancel"})

{: version
 : methods
 : initialize-params
 : parse-initialize
 : new-session-params
 : parse-new-session
 : load-params
 : list-params
 : parse-list
 : parse-load-session
 : set-config-params
 : parse-set-config-result
 : prompt-params
 : parse-prompt-result
 : cancel-params
 : parse-update
 : update-session-id
 : parse-permission
 : permission-selected
 : permission-cancelled
 : parse-elicitation
 : elicitation-accept
 : elicitation-declined
 : elicitation-cancelled}
