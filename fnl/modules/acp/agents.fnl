;; Agent profiles: the command to run for a named agent, and how to run it.
;;
;; vim.g.acp-agents maps a name to one of:
;;   an argv list        ["my-agent" "--acp"]
;;   a command string    "my-agent --acp"
;;   a profile table     {:cmd ["my-agent" "--acp"] :env-remove ["SOME_VAR"]}
;; and is merged over the built-in agents below: a built-in keeps the profile settings
;; an entry doesn't give (a bare command replaces only its :cmd).
;;
;; :env-remove lists environment variables the agent doesn't get. It defaults to
;; ANTHROPIC_API_KEY for every agent, built-in or not, so an agent that runs Claude
;; Code never bills the API instead of the subscription. An agent that needs the key
;; opts out with :env-remove [] (the built-in opencode does).
;;
;; The default agent is the one :Acp starts when none is named: vim.g.acp-config's
;; :agent, else claude. vim.g.acp-agent-cmd, when set, replaces the command of the
;; default agent (keeping its other profile settings) and wins over its
;; vim.g.acp-agents entry; other agents are not affected, so naming another agent
;; never runs the override.

(local default-env-remove ["ANTHROPIC_API_KEY"])

(local builtin
  {:claude {:cmd ["claude-agent-acp"]}
   :opencode {:cmd ["opencode" "acp"] :env-remove []}})

(fn parse-cmd [cmd]
  ;; A string is split on spaces, as vim.g.acp-agent-cmd always allowed.
  (if (= (type cmd) :string)
    (vim.split cmd " " {:trimempty true})
    (= (type cmd) :table)
    cmd))

(fn parse-entry [entry]
  ;; A vim.g.acp-agents value -> the profile fields it gives.
  (if (and (= (type entry) :table) (not (vim.islist entry)))
    {:cmd (parse-cmd entry.cmd) :env-remove entry.env-remove}
    {:cmd (parse-cmd entry)}))

(fn profiles []
  (let [all (vim.deepcopy builtin)]
    (each [name entry (pairs (or vim.g.acp-agents {}))]
      (let [given (parse-entry entry)
            p (vim.deepcopy (or (. all name) {}))]
        (when (and given.cmd (> (length given.cmd) 0))
          (set p.cmd given.cmd))
        (when (= (type given.env-remove) :table)
          (set p.env-remove given.env-remove))
        (when (and p.cmd (> (length p.cmd) 0))
          (tset all name p))))
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
  (let [p (. (profiles) name)
        override (when (= name (default-name)) (parse-cmd vim.g.acp-agent-cmd))]
    (when p
      {: name
       :cmd (if (and override (> (length override) 0)) override p.cmd)
       :env-remove (or p.env-remove default-env-remove)})))

{: names
 : default-name
 : get}
