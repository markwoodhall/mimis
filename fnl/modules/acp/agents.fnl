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
;; :credits-cmd is a command (argv list or string) whose output shows the account's
;; spend or credits in the statusline, refreshed after every turn; see
;; modules.acp.credits. The built-in opencode shows the last 30 days' spend.
;; :credits-cmd false turns it off for one agent.
;;
;; :sandbox runs the agent in a network namespace where the only way out is a proxy
;; that allows the hosts it lists and logs every attempt; see modules.acp.sandbox.
;; Sandboxed agents see the host read-only, but not $HOME: it is replaced with an
;; allowlist of toolchain paths, so ~/.ssh and ~/.aws are absent rather than merely
;; read-only. They may write only to the project, /tmp, the XDG data home and cache;
;; the project's .git/hooks, .git/config and .gitattributes stay read-only; see
;; modules.acp.sandbox.
;;   :sandbox false                     unsandboxed (the default)
;;   :sandbox true                      no host allowed
;;   :sandbox {:net false}              no network at all
;;   :sandbox {:net :proxy :allow ["api.anthropic.com:443"]}
;;   :sandbox {:net :proxy :allow [...]
;;             :read ["~/.config/gh"] :write ["~/.local/share/acme"]}
;; :read and :write add $HOME paths to the allowlist; :mask hides more paths.
;; A profile's :sandbox is the policy and the default. :Acp sandbox turns it on for one
;; session (an agent with no policy gets no host allowed), :Acp nosandbox turns it off.
;;
;; The default agent is the one :Acp starts when none is named: vim.g.acp-config's
;; :agent, else claude. vim.g.acp-agent-cmd, when set, replaces the command of the
;; default agent (keeping its other profile settings) and wins over its
;; vim.g.acp-agents entry; other agents are not affected, so naming another agent
;; never runs the override.

(local default-env-remove ["ANTHROPIC_API_KEY"])

(local builtin
  {:claude {:cmd ["claude-agent-acp"]}
   :opencode {:cmd ["opencode" "acp"]
              :env-remove []
              :credits-cmd ["opencode" "stats" "--days" "30" "--json"]}})

(fn parse-cmd [cmd]
  ;; A string is split on spaces, as vim.g.acp-agent-cmd always allowed.
  (if (= (type cmd) :string)
    (vim.split cmd " " {:trimempty true})
    (= (type cmd) :table)
    cmd))

(fn parse-entry [entry]
  ;; A vim.g.acp-agents value -> the profile fields it gives.
  (if (and (= (type entry) :table) (not (vim.islist entry)))
    {:cmd (parse-cmd entry.cmd)
     :env-remove entry.env-remove
     :sandbox entry.sandbox
     :credits-cmd (if (= entry.credits-cmd false) false (parse-cmd entry.credits-cmd))}
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
        (when (not= given.credits-cmd nil)
          (set p.credits-cmd given.credits-cmd))
        (when (not= given.sandbox nil)
          (set p.sandbox given.sandbox))
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
  ;; {:name :cmd :env-remove [VAR ...] :credits-cmd}, or nil if name isn't a configured
  ;; agent. :credits-cmd is nil when the agent has none.
  (let [p (. (profiles) name)
        override (when (= name (default-name)) (parse-cmd vim.g.acp-agent-cmd))]
    (when p
      {: name
       :cmd (if (and override (> (length override) 0)) override p.cmd)
       :env-remove (or p.env-remove default-env-remove)
       :sandbox p.sandbox
       :credits-cmd (when (and p.credits-cmd (> (length p.credits-cmd) 0)) p.credits-cmd)})))

{: names
 : default-name
 : get}
