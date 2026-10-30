;; ACP client: user commands. See fnl/modules/acp/ for the pieces.

(local session (require :modules.acp.session))
(local agents (require :modules.acp.agents))
(local render (require :modules.acp.render))
(local log (require :modules.acp.log))
(local summary (require :modules.acp.summary))
(local ui (require :modules.acp.ui))

(fn send [opts]
  (let [s (session.current)
        from-args? (and opts (not= opts.args ""))]
    (if (not s)
      (vim.notify "acp: no session, run :Acp first" vim.log.levels.WARN)
      (let [text (if from-args? opts.args (render.prompt-text s))]
        (when (and (not= text "")
                   (session.send-prompt s text)
                   (not from-args?))
          (render.clear-prompt s))))))

(fn cancel []
  (session.cancel (session.current)))

(fn quit []
  (session.stop (session.current)))

(fn setting-pairs [fargs]
  ;; ["model" "sonnet" "mode" "plan"] -> {:model "sonnet" :mode "plan"}
  (let [requested {}]
    (for [i 1 (length fargs) 2]
      (tset requested (. fargs i) (. fargs (+ i 1))))
    requested))

(fn sandbox-flag [arg]
  ;; :Acp's leading sandbox switch, if that's what this argument is. These two names
  ;; are therefore reserved and can't be agent names.
  (if (= arg "sandbox") true
      (= arg "nosandbox") false))

(fn setting-ids []
  ;; The settings the running session offers, or the last one did.
  (collect [_ o (ipairs (session.known-config))]
    (values o.id true)))

(fn parse-args [fargs]
  ;; ["sandbox" "opencode" "model" "x"] -> {:sandbox true :agent "opencode" :settings {:model "x"}}
  ;; ["nosandbox"]                     -> {:sandbox false :settings {}}
  ;; ["model" "x"]                     -> {:settings {:model "x"}}
  ;; A leading sandbox/nosandbox switches the session's sandbox for this invocation;
  ;; without one the agent's profile decides.
  ;; A first argument that names an agent (and isn't also a setting id) is the agent,
  ;; and what follows must be pairs. Otherwise all arguments are pairs, and an odd
  ;; count means the first one was meant as an agent that doesn't exist, or is also a
  ;; setting id (such an agent must be renamed: completion would be ambiguous).
  (let [flag (sandbox-flag (. fargs 1))
        fargs (if (= flag nil) fargs (vim.list_slice fargs 2))
        first (. fargs 1)
        agent? (and first (agents.get first) (not (. (setting-ids) first)))]
    (if agent?
      (if (= 0 (% (length fargs) 2))
        (values nil (.. "acp: settings come in pairs after the agent, e.g. :Acp "
                        first " model sonnet"))
        {:agent first :settings (setting-pairs (vim.list_slice fargs 2)) :sandbox flag})
      (= 0 (% (length fargs) 2))
      {:settings (setting-pairs fargs) :sandbox flag}
      (agents.get first)
      (values nil (.. "acp: '" first "' is both an agent and a setting of the agent, "
                      "rename the agent in vim.g.acp-agents"))
      (values nil (.. "acp: unknown agent '" first "' (known: "
                      (table.concat (agents.names) ", ")
                      "), or settings come in pairs")))))

(fn start-config []
  ;; vim.g.acp-config minus :agent, which picks the agent and is not a setting.
  (let [config (vim.deepcopy (or vim.g.acp-config {}))]
    (set config.agent nil)
    config))

(fn chat-row [s]
  (when (and s (= (vim.api.nvim_get_current_buf) s.buf))
    (. (vim.api.nvim_win_get_cursor 0) 1)))

(fn tool [opts]
  ;; In the chat, toggles the details of the tool call under the cursor.
  ;; Anywhere else, opens the latest tool call in a split.
  (let [s (session.current)
        row (chat-row s)]
    (if (not s)
      (vim.notify "acp: no session, run :Acp first" vim.log.levels.WARN)
      row
      (when (not (session.toggle-tool s row))
        (vim.notify "acp: no tool call on this line" vim.log.levels.WARN))
      (session.show-latest-tool s opts.mods))))

(fn chat-keymaps [s]
  ;; <CR> in the input area sends the prompt, on a permission choice answers it,
  ;; on a question opens its form, on a tool line toggles its details, anywhere
  ;; else does what <CR> normally does.
  ;; Expr mappings can't change text, so the actions run just after.
  (vim.keymap.set :n "<CR>"
                  (fn []
                    (let [row (chat-row s)]
                      (if (render.in-input? s row)
                        (do (vim.schedule send) "")
                        (session.choice-at s row)
                        (do (vim.schedule #(session.choose-at s row)) "")
                        (session.elicitation-at s row)
                        (do (vim.schedule #(session.answer-open s)) "")
                        (session.tool-at s row)
                        "<Cmd>AcpTool<CR>"
                        "<CR>")))
                  {:buffer s.buf :expr true
                   :desc "ACP send, answer permission, answer a question or toggle tool details"}))

(fn focus [s mods]
  ;; Shows the chat with the cursor on a waiting permission choice or question,
  ;; else in the input.
  (render.show s mods)
  (render.cursor-to s (or (session.first-choice-row s)
                          (session.first-elicitation-row s))))

(fn allow [opts]
  (session.choose-kind (session.current)
                       (if opts.bang [:allow_always :allow_once] [:allow_once :allow_always])))

(fn reject []
  (session.choose-kind (session.current) [:reject_once :reject_always]))

(fn answer []
  (session.answer-open (session.current)))

(fn decline []
  (session.decline-open (session.current)))

(fn sandbox-for [agent flag]
  ;; flag is :Acp's switch: true (asked for), false (asked against), nil (the profile
  ;; decides). Asking for one an agent has no policy for means no host is allowed.
  (if (= flag false)
    nil
    (or agent.sandbox (and flag true))))

(fn start-new [s name requested mods intent sandbox-flag]
  ;; Ends the current session, if any, and starts one with the named agent; with none
  ;; named, the current session's agent, else the default agent. intent says what the
  ;; session is for when it isn't just a new one, see session.start.
  (let [name (or name (and s s.agent.name) (agents.default-name))
        base (agents.get name)]
    (if (not base)
      (vim.notify (.. "acp: unknown agent '" name "' in vim.g.acp-config (known: "
                      (table.concat (agents.names) ", ") ")")
                  vim.log.levels.WARN)
      (do
        (when s
          (when (and (session.alive? s) (not= name s.agent.name))
            (vim.notify (.. "acp: switching agent from " s.agent.name " to " name)))
          (session.stop s))
        (let [agent (vim.deepcopy base)
              _ (tset agent :sandbox (sandbox-for base sandbox-flag))
              s (session.start agent (vim.tbl_extend :force (start-config) requested) intent)]
          (chat-keymaps s)
          (focus s mods))))))

(fn open [opts]
  ;; :Acp [sandbox|nosandbox] [agent] [setting value]...
  ;;   open or focus the session, changing any settings given; naming a different
  ;;   agent, or flipping the sandbox, starts a new session.
  ;; :Acp! ... end the current session and start a new one, with the same agent unless
  ;;   another is named.
  ;; New sessions start from vim.g.acp-config, with the arguments on top.
  (let [s (session.current)
        (parsed problem) (parse-args opts.fargs)]
    (if (not parsed)
      (vim.notify problem vim.log.levels.WARN)
      (and (session.alive? s) (not opts.bang)
           (or (not parsed.agent) (= parsed.agent s.agent.name))
           (or (= parsed.sandbox nil) (= parsed.sandbox (and s.sandbox true))))
      (do
        (when (next parsed.settings)
          (session.configure s parsed.settings))
        (focus s opts.mods))
      (start-new s parsed.agent parsed.settings opts.mods nil parsed.sandbox))))

(fn resume [opts]
  ;; :AcpResume [agent] [session-id]  choose an earlier session of this project to
  ;; continue; the chat replays it. With an id (or the start of one) it is loaded directly.
  ;; :AcpResume!  choose from the sessions of every project
  ;; The running session is only ended once a session is chosen.
  (let [s (session.current)
        fargs opts.fargs
        agent-name (when (agents.get (or (. fargs 1) "")) (. fargs 1))
        id (if agent-name (. fargs 2) (. fargs 1))
        name (or agent-name (and s s.agent.name) (agents.default-name))
        intent {:kind :pick :all? (or opts.bang (not= id nil)) : id}]
    (if (not (agents.get name))
      (vim.notify (.. "acp: unknown agent '" name "' (known: "
                      (table.concat (agents.names) ", ") ")")
                  vim.log.levels.WARN)
      (and (session.alive? s) s.ready (= name s.agent.name))
      (session.pick-live s intent
        (fn [chosen]
          (start-new s name {} opts.mods
                     {:kind :load :id chosen.id :cwd chosen.cwd :title chosen.title})))
      (start-new s name {} opts.mods intent))))

(fn show-summary [opts]
  ;; :AcpSummary  a markdown buffer of this project's logged sessions.
  ;; :AcpSummary!  every project's sessions. Command modifiers choose the split.
  (summary.open {:all? opts.bang :root (session.project-root) :mods opts.mods}))

(fn pick-value [s option]
  (ui.select option.values
             {:prompt (.. option.name ": ")
              :format_item (fn [v]
                             (.. (if (= v.value option.current) "* " "  ")
                                 v.name
                                 (if v.description (.. " — " v.description) "")))}
             (fn [v]
               (when v (session.set-config s option.id v.value)))))

(fn configure [opts]
  (let [s (session.current)
        [id value] opts.fargs]
    (if (not (session.alive? s))
      (vim.notify "acp: no running session, run :Acp first" vim.log.levels.WARN)
      (= (length (session.config s)) 0)
      (vim.notify "acp: the agent offers no settings" vim.log.levels.WARN)
      (not id)
      (ui.select (session.config s)
                 {:prompt "Setting: "
                  :format_item (fn [o] (.. o.name ": " o.display))}
                 (fn [o] (when o (pick-value s o))))
      (let [option (session.config-option s id)]
        (if (not option)
          (vim.notify (.. "acp: unknown setting " id) vim.log.levels.WARN)
          (not value)
          (pick-value s option)
          (session.configure s {id value}))))))

(fn complete-settings [max-pairs agents?]
  ;; Completes "setting value" pairs, from the running session or the last one seen.
  ;; With agents?, the first argument may also be an agent name, which shifts the pairs
  ;; by one, and with no argument at all the sandbox switches are offered too.
  (fn [arglead cmdline _]
    (let [known (session.known-config)
          ids (setting-ids)
          args (. (vim.api.nvim_parse_cmd cmdline {}) :args)
          skip (if (sandbox-flag (. args 1)) 1 0)
          done (if (= arglead "") (length args) (- (length args) 1))
          left (- done skip)
          lead (when (and agents? (> left 0)) (. args (+ skip 1)))
          offset (+ skip (if (and lead (agents.get lead) (not (. ids lead))) 1 0))
          candidates (if (>= (- done offset) (* 2 max-pairs))
                       []
                       (= 0 (% (- done offset) 2))
                       (let [given (collect [i a (ipairs args)]
                                     (when (and (> i offset) (<= i done) (= 1 (% (- i offset) 2)))
                                       (values a true)))
                             settings (icollect [_ o (ipairs known)]
                                        (when (not (. given o.id)) o.id))]
                         (if (and agents? (= left 0))
                           (vim.list_extend
                             (vim.list_extend
                               settings
                               (icollect [_ n (ipairs (agents.names))]
                                 (when (not (. ids n)) n)))
                             (if (= skip 0) ["sandbox" "nosandbox"] []))
                           settings))
                       (let [id (. args done)]
                         (accumulate [choices [] _ o (ipairs known)]
                           (if (= o.id id) o.values choices))))]
      (icollect [_ c (ipairs candidates)]
        (when (vim.startswith c arglead) c)))))

(fn enable [])

(fn highlights []
  ;; Make added/removed lines in ```diff blocks visibly different. Linking to the
  ;; DiffAdd/DiffDelete groups gives them green/red backgrounds in most colorschemes.
  (each [_ [group target] (ipairs [[:diffAdded :DiffAdd]
                                   [:diffRemoved :DiffDelete]
                                   [:diffChanged :DiffChange]
                                   ["@diff.plus" :DiffAdd]
                                   ["@diff.minus" :DiffDelete]
                                   ["@diff.delta" :DiffChange]])]
    (vim.api.nvim_set_hl 0 group {:link target :default false}))
  ;; Rows protected from markdown in render.markdown; keep their old blockquote look.
  (vim.api.nvim_set_hl 0 :AcpUiLine {:link :Normal :default false})
  (vim.api.nvim_set_hl 0 :AcpUiPrefix {:link :Comment :default false}))

(fn setup []
  (highlights)
  (vim.api.nvim_create_autocmd :ColorScheme
    {:group (vim.api.nvim_create_augroup "acp-hl" {:clear true})
     :desc "Reapply ACP highlights"
     :callback highlights})

  (when (not vim.g.markdown_fenced_languages)
    (set vim.g.markdown_fenced_languages
         [:clojure :fennel :sh :bash=sh :diff :json :lua :sql :python]))

  (vim.api.nvim_create_autocmd :VimLeavePre
    {:group (vim.api.nvim_create_augroup "acp" {:clear true})
     :desc "Stop the ACP agent"
     :callback #(session.shutdown)})

  (vim.api.nvim_create_user_command "Acp" open
    {:nargs "*" :bang true :complete (complete-settings 10 true)
     :desc "Open or focus the ACP session; ! starts a new one; args are sandbox|nosandbox, an optional agent, then setting/value pairs"})
  (vim.api.nvim_create_user_command "AcpResume" resume
    {:nargs "*" :bang true
     :complete (fn [arglead _ _]
                 (icollect [_ n (ipairs (agents.names))]
                   (when (vim.startswith n arglead) n)))
     :desc "Resume an earlier ACP session of this project; ! lists every project's; args are an optional agent and session id"})
  (vim.api.nvim_create_user_command "AcpSummary" show-summary
    {:bang true
     :desc "Show a markdown summary of this project's ACP session logs; ! includes every project"})
  (vim.api.nvim_create_user_command "AcpConfig" configure
    {:nargs "*" :complete (complete-settings 1)
     :desc "Show or change ACP session settings (model, mode, effort...)"})
  (vim.api.nvim_create_user_command "AcpSend" send
    {:nargs "*" :desc "Send the prompt buffer, or the given text, to the ACP agent"})
  (vim.api.nvim_create_user_command "AcpCancel" cancel {:desc "Cancel the running ACP turn"})
  (vim.api.nvim_create_user_command "AcpStop" quit {:desc "End the ACP session"})
  (vim.api.nvim_create_user_command "AcpAllow" allow
    {:bang true :desc "Allow the agent's permission request once (! to always allow)"})
  (vim.api.nvim_create_user_command "AcpReject" reject
    {:desc "Reject the agent's permission request"})
  (vim.api.nvim_create_user_command "AcpAnswer" answer
    {:desc "Answer the agent's question (form elicitation); <CR> on its line does the same"})
  (vim.api.nvim_create_user_command "AcpDecline" decline
    {:desc "Decline the agent's question"})
  (vim.api.nvim_create_user_command "AcpTool" tool
    {:desc "Toggle the details of the tool call under the cursor, or show the latest one"})
  (vim.api.nvim_create_user_command "AcpOpenBlock" render.open-code-block
    {:desc "Open the fenced code block under the cursor in its own buffer"})
  (vim.api.nvim_create_user_command
    "AcpGrep"
    (fn [opts]
      (vim.cmd (.. "silent grep! " (vim.fn.shellescape opts.args 1) " " (vim.fn.fnameescape (log.log-dir)))))
    {:nargs "+" :desc "Search ACP session logs"}))

{: enable
 : setup
 : parse-args}
