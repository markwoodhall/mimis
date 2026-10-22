;; Agent profiles: the command to run for a named agent, and how to run it.
;;
;; vim.g.acp-agents maps a name to an argv list (or a command string) and is merged
;; over the built-in agents below: a built-in keeps its other profile settings
;; (env-remove) when only its command is replaced.
;;
;; The default agent is the one :Acp starts when none is named: vim.g.acp-config's
;; :agent, else claude. vim.g.acp-agent-cmd, when set, replaces the command of the
;; default agent and wins over its vim.g.acp-agents entry; other agents are not
;; affected, so naming another agent never runs the override.

(local builtin
  {:claude {:cmd ["claude-agent-acp"]
            ;; Never pass an API key through, or Claude Code bills the API instead of
            ;; the subscription.
            :env-remove ["ANTHROPIC_API_KEY"]}
   :opencode {:cmd ["opencode" "acp"]}})

(fn parse-cmd [cmd]
  ;; A string is split on spaces, as vim.g.acp-agent-cmd always allowed.
  (if (= (type cmd) :string)
    (vim.split cmd " " {:trimempty true})
    (= (type cmd) :table)
    cmd))

(fn profiles []
  (let [all (vim.deepcopy builtin)]
    (each [name cmd (pairs (or vim.g.acp-agents {}))]
      (let [argv (parse-cmd cmd)]
        (when (and argv (> (length argv) 0))
          (tset all name (vim.tbl_extend :force (or (. all name) {}) {:cmd argv})))))
    all))

(fn names []
  (let [found (vim.tbl_keys (profiles))]
    (table.sort found)
    found))

(fn default-name []
  (let [name (?. vim.g.acp-config :agent)]
    (if (= (type name) :string) name "claude")))

(fn get [name]
  ;; {:name :cmd :env-remove [VAR ...]}, or nil if name isn't a configured agent.
  (let [p (. (profiles) name)]
    (when p
      {: name
       :cmd (or (when (= name (default-name)) (parse-cmd vim.g.acp-agent-cmd)) p.cmd)
       :env-remove (or p.env-remove [])})))

{: names
 : default-name
 : get}
