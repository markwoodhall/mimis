;; ACP client: user commands. See fnl/modules/acp/ for the pieces.

(local session (require :modules.acp.session))
(local agents (require :modules.acp.agents))
(local broker (require :modules.acp.broker))
(local handoff (require :modules.acp.handoff))
(local render (require :modules.acp.render))
(local log (require :modules.acp.log))
(local threads (require :modules.acp.threads))
(local usage (require :modules.acp.usage))
(local sandbox (require :modules.acp.sandbox))

(fn send [opts]
  (let [s (session.here)
        from-args? (and opts (not= opts.args ""))]
    (if (not s)
      (vim.notify "acp: no session, run :Acp first" vim.log.levels.WARN)
      (let [text (if from-args? opts.args (render.prompt-text s))]
        (when (and (not= text "")
                   (session.send-prompt s text)
                   (not from-args?))
          (render.clear-prompt s))))))

(fn cancel []
  (session.cancel (session.here)))

(fn quit []
  (session.stop (session.here)))

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

(fn path-grant [arg]
  ;; :Acp's read=PATH or write=PATH, a path to expose to this session's sandbox, as
  ;; :read or :write in a profile would. Resolved here, so ./data means this directory.
  (let [(kind path) (string.match (or arg "") "^(%a+)=(.+)$")]
    (when (or (= kind "read") (= kind "write"))
      (values kind (vim.fs.normalize (vim.fn.fnamemodify (vim.fn.expand path) ":p"))))))

(fn known-settings [name]
  ;; What the named agent offers, or with none named the agent a new :Acp would use.
  (session.known-config (or name
                            (?. (session.current) :agent :name)
                            (agents.default-name))))

(fn setting-ids []
  ;; The settings of the agent in use, which is as much as can be known before the
  ;; arguments have been told apart.
  (collect [_ o (ipairs (known-settings))]
    (values o.id true)))

(fn parse-args [fargs]
  ;; ["sandbox" "opencode" "model" "x"] -> {:sandbox true :agent "opencode" :settings {:model "x"}}
  ;; ["nosandbox"]                     -> {:sandbox false :settings {}}
  ;; ["model" "x"]                     -> {:settings {:model "x"}}
  ;; ["write=/mnt/x" "model" "x"]      -> {:settings {:model "x"} :paths {:read [] :write ["/mnt/x"]}}
  ;;                                       (no :paths when none are given)
  ;; A leading sandbox/nosandbox switches the session's sandbox for this invocation;
  ;; without one the agent's profile decides.
  ;; read=PATH and write=PATH, anywhere, add to the sandbox's :read and :write.
  ;; A first argument that names an agent (and isn't also a setting id) is the agent,
  ;; and what follows must be pairs. Otherwise all arguments are pairs, and an odd
  ;; count means the first one was meant as an agent that doesn't exist, or is also a
  ;; setting id (such an agent must be renamed: completion would be ambiguous).
  (let [grants {:read [] :write []}
        fargs (icollect [_ arg (ipairs fargs)]
                (let [(kind path) (path-grant arg)]
                  (if kind
                    (do (table.insert (. grants kind) path) nil)
                    arg)))
        paths (when (or (next grants.read) (next grants.write)) grants)
        flag (sandbox-flag (. fargs 1))
        fargs (if (= flag nil) fargs (vim.list_slice fargs 2))
        first (. fargs 1)
        agent? (and first (agents.get first) (not (. (setting-ids) first)))]
    (if agent?
      (if (= 0 (% (length fargs) 2))
        (values nil (.. "acp: settings come in pairs after the agent, e.g. :Acp "
                        first " model sonnet"))
        {:agent first :settings (setting-pairs (vim.list_slice fargs 2)) :sandbox flag : paths})
      (= 0 (% (length fargs) 2))
      {:settings (setting-pairs fargs) :sandbox flag : paths}
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
  (let [s (session.here)
        row (chat-row s)]
    (if (not s)
      (vim.notify "acp: no session, run :Acp first" vim.log.levels.WARN)
      row
      (when (not (session.toggle-tool s row))
        (vim.notify "acp: no tool call on this line" vim.log.levels.WARN))
      (session.show-latest-tool s opts.mods))))

(fn chat-keymaps [s]
  ;; <CR> in the input area sends the prompt, on a permission or egress choice
  ;; answers it, on a question opens its form, on a tool line toggles its details,
  ;; anywhere else does what <CR> normally does.
  ;; Expr mappings can't change text, so the actions run just after.
  (vim.keymap.set :n "<CR>"
                  (fn []
                    (let [row (chat-row s)]
                      (if (render.in-input? s row)
                        (do (vim.schedule send) "")
                        (session.choice-at s row)
                        (do (vim.schedule #(session.choose-at s row)) "")
                        (session.egress-choice-at s row)
                        (do (vim.schedule #(session.choose-egress-at s row)) "")
                        (session.elicitation-at s row)
                        (do (vim.schedule #(session.answer-open s)) "")
                        (session.tool-at s row)
                        "<Cmd>AcpTool<CR>"
                        (session.comment-action s row)
                        (do (vim.schedule (session.comment-action s row)) "")
                        "<CR>")))
                  {:buffer s.buf :expr true
                   :desc "ACP send, answer permission, answer a question, toggle tool details or send a comment"})
  ;; gc comments on the block under the cursor (or a heading's section) or on the lines
  ;; selected: a thread opens under their block, in insert mode. In a thread, it's a
  ;; follow-up at the thread's end.
  (let [write-at (fn [row why]
                   (if row
                     (do (vim.api.nvim_win_set_cursor 0 [row 0])
                         (vim.cmd "startinsert!"))
                     (vim.notify (.. "acp: " why) vim.log.levels.WARN)))
        open-comment (fn [from to selected?] (write-at (render.add-comment s from to selected?)))]
    (vim.keymap.set :n "gc" #(let [row (chat-row s)] (open-comment row row))
                    {:buffer s.buf :nowait true :desc "ACP comment on this line of the chat"})
    (vim.keymap.set :x "gc" #(let [a (vim.fn.line "v")
                                   b (vim.fn.line ".")]
                               ;; :normal!, not feedkeys, which would run what's typed
                               ;; ahead (the comment) before insert mode starts.
                               (vim.cmd.normal {:args [(vim.keycode "<Esc>")] :bang true})
                               (open-comment (math.min a b) (math.max a b) true))
                    {:buffer s.buf :nowait true :desc "ACP comment on the selected lines of the chat"})))

(fn focus [s mods]
  ;; Shows the chat with the cursor on a waiting permission choice or question,
  ;; else in the input.
  (render.show s mods)
  (render.cursor-to s (or (session.first-choice-row s)
                          (session.first-elicitation-row s))))

(fn allow [opts]
  ;; These answer the session whose chat you're in, never a delegated agent you can't see.
  (session.choose-kind (session.here)
                       (if opts.bang [:allow_always :allow_once] [:allow_once :allow_always])))

(fn reject []
  (session.choose-kind (session.here) [:reject_once :reject_always]))

(fn answer []
  (session.answer-open (session.here)))

(fn decline []
  (session.decline-open (session.here)))

(fn sandbox-for [agent flag paths]
  ;; flag is :Acp's switch: true (asked for), false (asked against), nil (the profile
  ;; decides). Asking for one an agent has no policy for means no host is allowed.
  ;; paths are :Acp's read= and write= grants, added to the profile's; an unsandboxed
  ;; session can reach them anyway.
  (let [spec (sandbox.normalize (if (= flag false)
                                  nil
                                  (or agent.sandbox (and flag true))))]
    (when spec
      (vim.list_extend spec.read (or (?. paths :read) []))
      (vim.list_extend spec.write (or (?. paths :write) [])))
    spec))

(fn start-new [s name requested mods intent sandbox-flag paths]
  ;; Ends s, if given, and starts a session with the named agent; with none named, s's
  ;; agent, else the default agent. Other sessions keep running. intent says what the
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
              _ (tset agent :sandbox (sandbox-for base sandbox-flag paths))
              (delegation problem) (broker.open agent chat-keymaps)
              s (session.start agent (vim.tbl_extend :force (start-config) requested) intent
                               (when delegation (broker.session-options delegation)))]
          (when delegation (broker.attach delegation s))
          (when problem (vim.notify (.. "acp: " problem) vim.log.levels.WARN))
          (chat-keymaps s)
          (handoff.flush s)
          (focus s mods))))))

(fn open [opts]
  ;; :Acp [sandbox|nosandbox] [read=PATH|write=PATH]... [agent] [setting value]...
  ;;   open or focus the session, changing any settings given; naming a different
  ;;   agent, flipping the sandbox, or giving a path starts a new session, as a running
  ;;   sandbox's mounts can't be changed.
  ;; :Acp! ... end the current session and start a new one, with the same agent unless
  ;;   another is named.
  ;; New sessions start from vim.g.acp-config, with the arguments on top.
  ;; Several sessions can run at once: this acts on the chat you're in, else on the one
  ;; last used in this project. Another project's session is left running.
  (let [here (session.here)
        s (if (and here (= here.buf (vim.api.nvim_get_current_buf)))
            here
            (session.project-session (session.project-root)))
        (parsed problem) (parse-args opts.fargs)]
    (if (not parsed)
      (vim.notify problem vim.log.levels.WARN)
      (and (session.alive? s) (not opts.bang)
           (or (not parsed.agent) (= parsed.agent s.agent.name))
           (or (= parsed.sandbox nil) (= parsed.sandbox (and s.sandbox true)))
           (not parsed.paths))
      (do
        (when (next parsed.settings)
          (session.configure s parsed.settings))
        (focus s opts.mods))
      (start-new s parsed.agent parsed.settings opts.mods nil parsed.sandbox parsed.paths))))

(fn resume [opts]
  ;; :AcpResume [agent] [session-id]  choose an earlier session of this project to
  ;; continue; the chat replays it. With an id (or the start of one) it is loaded directly.
  ;; :AcpResume!  choose from the sessions of every project
  ;; The chosen session runs alongside any others; one already running is just shown.
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
          (let [running (session.with-id chosen.id)]
            (if running
              (focus running opts.mods)
              (start-new nil name {} opts.mods
                         {:kind :load :id chosen.id :cwd chosen.cwd :title chosen.title})))))
      (start-new nil name {} opts.mods intent))))

(fn show-agents [opts]
  ;; :AcpAgents  choose between a session and the agents it delegated to, and jump there.
  (let [s (session.here)
        root (when s (or s.parent s))
        family (when root (vim.list_extend [root] (session.children root)))]
    (if (or (not root) (= 1 (length family)))
      (vim.notify "acp: no delegated agents" vim.log.levels.WARN)
      (vim.ui.select family
                     {:prompt "Agent: "
                      :format_item (fn [a]
                                     (let [waiting (session.waiting-for a)]
                                       (.. (or a.label a.agent.name) " — " (session.state a)
                                           (if (> (length waiting) 0)
                                             (.. " — " (. waiting 1))
                                             (?. a :activity :label)
                                             (.. " — " a.activity.label)
                                             ""))))}
                     (fn [a]
                       (when a (focus a opts.mods)))))))

(fn jump-waiting []
  ;; :AcpWaiting  goes to a chat waiting on you, with the cursor on what it asks: the
  ;; next one after the chat you're in, so doing it again visits each in turn.
  (let [all (session.waiting)
        here (session.here)
        at (accumulate [found nil i s (ipairs all) &until found]
             (when (and (= s here) (= s.buf (vim.api.nvim_get_current_buf))) i))
        target (. all (if at (+ (% at (length all)) 1) 1))]
    (if target
      (focus target "")
      (vim.notify "acp: nothing is waiting on you"))))

(fn show-threads []
  ;; :AcpThreads  the sidebar of every thread; see modules.acp.threads. Each action runs
  ;; in the window beside it, its directory already the thread's project.
  (let [agent-for (fn [t]
                    (or (?. t :live :agent :name)
                        (when (agents.get (or t.agent-name "")) t.agent-name)
                        (agents.default-name)))]
    (threads.open
      {:show (fn [s] (focus s ""))
       :resume (fn [t]
                 (start-new nil (agent-for t) {} ""
                            {:kind :load :id t.id :cwd t.cwd :title t.title}))
       :new (fn [t]
              (start-new nil (agent-for t) {} "" {:kind :new :cwd t.cwd}))})))

(fn pick-value [s option]
  (vim.ui.select option.values
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
      (vim.ui.select (session.config s)
                     {:prompt "Setting: "
                      :format_item (fn [o] (.. o.name ": " o.display))}
                     (fn [o] (when o (pick-value s o))))
      (let [option (session.config-option s id)]
        (if (not option)
          (vim.notify (.. "acp: unknown setting " id) vim.log.levels.WARN)
          (not value)
          (pick-value s option)
          (session.configure s {id value}))))))

(fn complete-pairs [max-pairs agents?]
  (fn [arglead cmdline]
    (let [ids (setting-ids)
          args (icollect [_ a (ipairs (. (vim.api.nvim_parse_cmd cmdline {}) :args))]
                 (when (not (path-grant a)) a))
          skip (if (sandbox-flag (. args 1)) 1 0)
          done (if (= arglead "") (length args) (- (length args) 1))
          left (- done skip)
          lead (when (and agents? (> left 0)) (. args (+ skip 1)))
          named (when (and lead (agents.get lead) (not (. ids lead))) lead)
          offset (+ skip (if named 1 0))
          known (known-settings named)
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
                             (vim.list_extend
                               (if (= skip 0) ["sandbox" "nosandbox"] [])
                               ["read=" "write="]))
                           settings))
                       (let [id (. args done)]
                         (accumulate [choices [] _ o (ipairs known)]
                           (if (= o.id id) o.values choices))))]
      (icollect [_ c (ipairs candidates)]
        (when (vim.startswith c arglead) c)))))

(fn complete-settings [max-pairs agents?]
  ;; Completes "setting value" pairs, of the agent named if any, else the agent in use.
  ;; With agents?, the first argument may also be an agent name, which shifts the pairs
  ;; by one, and with no argument at all the sandbox switches are offered too.
  ;; read=PATH and write=PATH complete as paths and are otherwise ignored.
  (fn [arglead cmdline _]
    (let [(kind path) (string.match arglead "^(%a+=)(.*)$")]
      (if (or (= kind "read=") (= kind "write="))
        (icollect [_ f (ipairs (vim.fn.getcompletion path :dir))]
          (.. kind f))
        ((complete-pairs max-pairs agents?) arglead cmdline)))))

(fn screenshot [opts]
  ;; :AcpScreenshot  select a region or window after a few seconds, to get to another
  ;; workspace; :AcpScreenshot N  after N seconds, 0 for straight away;
  ;; :AcpScreenshot clipboard  the copied image.
  (let [seconds (tonumber (string.match opts.args "^%d+$"))]
    (if (or seconds (= opts.args ""))
      (handoff.screenshot nil seconds)
      (= opts.args "clipboard")
      (handoff.screenshot :clipboard)
      (vim.notify (.. "acp: unknown screenshot source '" opts.args "'") vim.log.levels.WARN))))

(fn enable [])

(fn blend [fg bg alpha]
  ;; fg mixed into bg, alpha of the way: colours as 0xRRGGBB numbers.
  (let [channel (fn [c shift] (bit.band (bit.rshift c shift) 0xff))
        mix (fn [shift]
              (math.floor (+ 0.5 (* alpha (channel fg shift))
                             (* (- 1 alpha) (channel bg shift)))))]
    (+ (bit.lshift (mix 16) 16) (bit.lshift (mix 8) 8) (mix 0))))

(fn colour [value]
  ;; A palette's "#rrggbb", or a highlight's number, as a number.
  (if (= (type value) :string) (tonumber (value:sub 2) 16) value))

(fn shade-highlights []
  ;; Backgrounds for your prompts and the agent's replies in the chat: the editor's
  ;; background with a little of blue and of mauve in it. The prompt you're writing
  ;; is a plain grey (Catppuccin's surface0, else a little of the text colour), so it
  ;; reads as the one being edited. Catppuccin's palette if it's there, else the colourscheme's Function,
  ;; Statement and Normal colours. An egress you allowed has a green background, so a
  ;; way out of the sandbox is never missed.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        group (fn [name] (vim.api.nvim_get_hl 0 {: name :link false}))
        bg (colour (or (?. c :base) (. (group :Normal) :bg)))
        you (colour (or (?. c :blue) (. (group :Function) :fg)))
        agent (colour (or (?. c :mauve) (. (group :Statement) :fg)))
        grey (colour (or (?. c :surface0) (. (group :Normal) :fg)))
        thread (colour (or (?. c :teal) (. (group :DiagnosticInfo) :fg)))
        green (colour (or (?. c :green) (. (group :DiagnosticOk) :fg)))]
    (if (and bg you agent)
      (do
        (vim.api.nvim_set_hl 0 :AcpYou {:bg (blend you bg 0.14) :default false})
        (vim.api.nvim_set_hl 0 :AcpAgent {:bg (blend agent bg 0.05) :default false})
        ;; The bar beside your prompts: blue, brighter for the one being written; and
        ;; beside the agent's replies, mauve.
        (vim.api.nvim_set_hl 0 :AcpYouBar {:fg (blend you bg 0.6) :default false})
        (vim.api.nvim_set_hl 0 :AcpInputBar {:fg you :default false})
        (vim.api.nvim_set_hl 0 :AcpAgentBar {:fg (blend agent bg 0.6) :default false})
        ;; A comment's thread, inline in a reply: your comment in your prompts' shade
        ;; and the reply to it in the agent's, so who said what reads as it does in
        ;; the rest of the chat; the bars beside both in teal, for a thread.
        (let [thread (or thread agent)]
          (vim.api.nvim_set_hl 0 :AcpCommentYou {:bg (blend you bg 0.14) :default false})
          (vim.api.nvim_set_hl 0 :AcpCommentAgent {:bg (blend agent bg 0.05) :default false})
          (vim.api.nvim_set_hl 0 :AcpCommentYouBar {:fg thread :default false})
          (vim.api.nvim_set_hl 0 :AcpCommentAgentBar {:fg (blend thread bg 0.6) :default false})
          ;; The labels at the top of your comment and of the reply.
          (vim.api.nvim_set_hl 0 :AcpCommentLabel {:fg thread :bold true :default false})
          ;; The bar beside the lines a comment is about.
          (vim.api.nvim_set_hl 0 :AcpCommentMark {:fg thread :default false})
          (vim.api.nvim_set_hl 0 :AcpCommentMarkYou {:fg thread :default false})))
      (do
        (vim.api.nvim_set_hl 0 :AcpCommentYou {:link :CursorLine :default false})
        (vim.api.nvim_set_hl 0 :AcpCommentAgent {:default false})
        (vim.api.nvim_set_hl 0 :AcpCommentYouBar {:link :DiagnosticInfo :default false})
        (vim.api.nvim_set_hl 0 :AcpCommentAgentBar {:link :DiagnosticInfo :default false})
        (vim.api.nvim_set_hl 0 :AcpCommentMark {:link :DiagnosticInfo :default false})
        (vim.api.nvim_set_hl 0 :AcpCommentLabel {:link :DiagnosticInfo :default false})
        (vim.api.nvim_set_hl 0 :AcpCommentMarkYou {:link :DiagnosticInfo :default false})
        (vim.api.nvim_set_hl 0 :AcpYou {:link :CursorLine :default false})
        (vim.api.nvim_set_hl 0 :AcpAgent {:default false})
        (vim.api.nvim_set_hl 0 :AcpYouBar {:link :Comment :default false})
        (vim.api.nvim_set_hl 0 :AcpInputBar {:link :Function :default false})
        (vim.api.nvim_set_hl 0 :AcpAgentBar {:link :Statement :default false})))
    (vim.api.nvim_set_hl 0 :AcpInput
                         (if (and bg grey)
                           {:bg (if c grey (blend grey bg 0.1)) :default false}
                           {:link :CursorLine :default false}))
    ;; Each bar is drawn on its block's shade, as the gutter's padding is, so the block
    ;; starts at the bar and its text sits inside it.
    (each [bar block (pairs {:AcpYouBar :AcpYou :AcpInputBar :AcpInput :AcpAgentBar :AcpAgent
                             :AcpCommentYouBar :AcpCommentYou :AcpCommentAgentBar :AcpCommentAgent
                             :AcpCommentMark :AcpAgent :AcpCommentMarkYou :AcpYou})]
      (let [look (vim.api.nvim_get_hl 0 {:name bar :link false})
            shade (. (vim.api.nvim_get_hl 0 {:name block :link false}) :bg)]
        (vim.api.nvim_set_hl 0 bar (vim.tbl_extend :force look {:bg shade :default false}))))
    (vim.api.nvim_set_hl 0 :AcpEgressAllowed
                         (if (and bg green)
                           {:bg (blend green bg 0.25) :bold true :default false}
                           {:link :DiffAdd :default false}))))

(fn code-highlights []
  ;; A code block's card: darker than the chat, Catppuccin's mantle; its language muted.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        normal (. (vim.api.nvim_get_hl 0 {:name :Normal :link false}) :bg)]
    (vim.api.nvim_set_hl 0 :AcpCodeBlock
                         (if c {:bg (colour c.mantle) :default false}
                             normal {:bg (blend 0 normal 0.25) :default false}
                             {:link :ColorColumn :default false}))
    (vim.api.nvim_set_hl 0 :AcpCodeLang {:link :AcpUiPrefix :default false})
    ;; A diff's added and removed lines, the whole row, over the card.
    (vim.api.nvim_set_hl 0 :AcpDiffAddLine {:link :DiffAdd :default false})
    (vim.api.nvim_set_hl 0 :AcpDiffDelLine {:link :DiffDelete :default false})
    ;; A quote: the same card, a bar in the accent colour, its text in italic.
    (vim.api.nvim_set_hl 0 :AcpQuoteBlock {:link :AcpCodeBlock :default false})
    (vim.api.nvim_set_hl 0 :AcpQuoteBar
                         (if c {:fg (colour c.lavender) :default false} {:link :Function :default false}))
    (vim.api.nvim_set_hl 0 :AcpQuoteText {:italic true :default false})))

(fn thread-highlights []
  ;; The threads sidebar's panel and its rows' tints, from the chat's shades.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        bg (fn [name] (. (vim.api.nvim_get_hl 0 {: name :link false}) :bg))]
    (vim.api.nvim_set_hl 0 :AcpThreadsNormal
                         (if c {:bg (colour c.mantle) :default false} {:link :NormalFloat :default false}))
    (vim.api.nvim_set_hl 0 :AcpThreadsSeparator
                         (if c {:fg (colour c.mantle) :bg (colour c.mantle) :default false}
                             {:link :WinSeparator :default false}))
    (vim.api.nvim_set_hl 0 :AcpThreadsCursor {:bg (bg :AcpInput) :default false})
    (vim.api.nvim_set_hl 0 :AcpThreadsShown {:bg (bg :AcpAgent) :default false})
    ;; The chat's heading rule's colour, on the panel rather than a reply's shade.
    (vim.api.nvim_set_hl 0 :AcpThreadsRule
                         {:fg (. (vim.api.nvim_get_hl 0 {:name :AcpHeadingRule :link false}) :fg)
                          :default false})))

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
  ;; The tool, permission, note and thinking rows are muted, a way from their colour
  ;; towards the background, so the conversation has the focus. What needs you keeps
  ;; its full colour: a failed tool, a question waiting, an egress you allowed.
  (let [normal (vim.api.nvim_get_hl 0 {:name :Normal :link false})
        quiet (fn [name group extra]
                (let [fg (. (vim.api.nvim_get_hl 0 {:name group :link false}) :fg)]
                  (vim.api.nvim_set_hl 0 name
                                       (if (and fg normal.bg)
                                         (vim.tbl_extend :force {:fg (blend fg normal.bg 0.6) :default false}
                                                         (or extra {}))
                                         (vim.tbl_extend :force {:link group :default false}
                                                         (or extra {}))))))]
    ;; Rows protected from markdown in render.markdown.
    (quiet :AcpUiLine :Normal)
    (vim.api.nvim_set_hl 0 :AcpUiPrefix {:link :Comment :default false})
    ;; Icons on the chat's tool, permission and other UI rows.
    (quiet :AcpToolDone :DiagnosticOk)
    (quiet :AcpToolRunning :DiagnosticWarn)
    (vim.api.nvim_set_hl 0 :AcpToolFailed {:link :DiagnosticError :default false})
    (vim.api.nvim_set_hl 0 :AcpAttention {:link :WarningMsg :default false})
    ;; A tool's diff counts, +4 -0.
    (quiet :AcpDiffAdded :Added)
    (quiet :AcpDiffRemoved :Removed)
    ;; File names in those rows: underlined, but not bold, in their muted colour.
    (quiet :AcpPathQuiet :Normal {:underline true})
    ;; Folded thinking, the chat's Folded.
    (quiet :AcpFolded :Comment {:italic true})
    ;; What a comment's heading says about it: <CR> sends, queued, replying.
    (vim.api.nvim_set_hl 0 :AcpComment {:link :DiagnosticInfo :default false}))
  ;; Files the chat names.
  (vim.api.nvim_set_hl 0 :AcpPath {:bold true :underline true :default false})
  ;; The threads sidebar, in the chat's own colours: the heading like the agent's name
  ;; in the input; projects like the agent's ## headings; ages muted like a prompt's
  ;; time; the thread shown beside it in the agent's shade, its title in mauve; running
  ;; dots like the tool rows' icons. The panel is the statusline's mantle, its cursor
  ;; row the input's grey.
  (vim.api.nvim_set_hl 0 :AcpThreadsHeading {:link :AcpTurnAgent :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsGroup {:link :AcpH2 :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsTitle {:link :Normal :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsCurrent {:link :AcpTurnAgent :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsMeta {:link :AcpUiPrefix :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsMore {:link :AcpFolded :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsLive {:link :AcpToolDone :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsWorking {:link :AcpToolRunning :default false})
  (vim.api.nvim_set_hl 0 :AcpThreadsWaiting {:link :AcpAttention :default false})
  ;; The choice the cursor is on, of a permission or question: the accent colour behind
  ;; the editor's background colour, as a pill.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        normal (vim.api.nvim_get_hl 0 {:name :Normal :link false})
        accent (colour (or (?. c :blue) (. (vim.api.nvim_get_hl 0 {:name :Function :link false}) :fg)))]
    (vim.api.nvim_set_hl 0 :AcpChoiceSelected
                         (if accent
                           {:bg accent :fg (colour (or (?. c :base) normal.bg)) :bold true :default false}
                           {:link :Visual :default false}))
    (vim.api.nvim_set_hl 0 :AcpChoiceArrow
                         (if accent {:fg accent :default false} {:link :Function :default false})))
  ;; In the chat, bold text is peach and code green, so a long reply's structure
  ;; shows at a glance; and a turn's footer starts with the agent, in mauve.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        fg (fn [name] (. (vim.api.nvim_get_hl 0 {: name :link false}) :fg))]
    (vim.api.nvim_set_hl 0 :AcpBold {:fg (colour (or (?. c :peach) (fg :Constant))) :bold true :default false})
    (vim.api.nvim_set_hl 0 :AcpCode {:fg (colour (or (?. c :green) (fg :String))) :default false})
    (vim.api.nvim_set_hl 0 :AcpTurnAgent {:fg (colour (or (?. c :mauve) (fg :Statement))) :bold true :default false}))
  ;; Mermaid diagrams drawn in the chat.
  (vim.api.nvim_set_hl 0 :AcpDiagram {:link :Normal :default false})
  ;; Headings in the chat, which maps markdownH1..6 to these: the colourscheme's
  ;; heading colours (Title's if it has none), bold. Turn headings stay quiet, and a
  ;; faint rule goes under the agent's # and ## headings.
  (for [level 1 6]
    (let [own (vim.api.nvim_get_hl 0 {:name (.. "markdownH" level) :link false})
          title (vim.api.nvim_get_hl 0 {:name :Title :link false})]
      (vim.api.nvim_set_hl 0 (.. "AcpH" level) {:fg (or own.fg title.fg) :bold true :default false})))
  (vim.api.nvim_set_hl 0 :AcpTurn {:link :Comment :default false})
  ;; Markdown tables in the chat.
  (vim.api.nvim_set_hl 0 :AcpTablePipe {:link :Comment :default false})
  (vim.api.nvim_set_hl 0 :AcpTableRule {:link :Comment :default false})
  (vim.api.nvim_set_hl 0 :AcpTableHeader {:bold true :default false})
  (shade-highlights)
  ;; The rule: a third of the way from the reply's shade to Comment, faint but there.
  ;; It's a virtual line, which the shading can't reach, so it has the reply's shade
  ;; behind it itself, or it would cut the heading off from the text under it.
  (let [shade (. (vim.api.nvim_get_hl 0 {:name :AcpAgent :link false}) :bg)
        bg (or shade (. (vim.api.nvim_get_hl 0 {:name :Normal :link false}) :bg))
        fg (. (vim.api.nvim_get_hl 0 {:name :Comment :link false}) :fg)]
    (vim.api.nvim_set_hl 0 :AcpHeadingRule (if (and bg fg)
                                             {:fg (blend fg bg 0.35) :bg shade :default false}
                                             {:link :Comment :default false})))
  ;; After the shades and the rule, which the sidebar's colours are made from.
  (thread-highlights)
  (code-highlights)
  (usage.highlights))

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
     :desc "Open or focus the ACP session; ! starts a new one; args are sandbox|nosandbox, read=PATH|write=PATH to expose to the sandbox, an optional agent, then setting/value pairs"})
  (vim.api.nvim_create_user_command "AcpResume" resume
    {:nargs "*" :bang true
     :complete (fn [arglead _ _]
                 (icollect [_ n (ipairs (agents.names))]
                   (when (vim.startswith n arglead) n)))
     :desc "Resume an earlier ACP session of this project; ! lists every project's; args are an optional agent and session id"})
  (vim.api.nvim_create_user_command "AcpAgents" show-agents
    {:desc "Choose between the ACP session and the agents it delegated to, and jump there"})
  (vim.api.nvim_create_user_command "AcpWaiting" jump-waiting
    {:desc "Go to an ACP chat waiting on you, its question under the cursor; again for the next"})
  ;; "go to waiting"; Vim leaves gW unused (gw formats).
  (vim.keymap.set :n "gW" "<Cmd>AcpWaiting<CR>"
                  {:desc "Go to an ACP chat waiting on you"})
  (vim.api.nvim_create_user_command "AcpThreads" show-threads
    {:desc "Toggle a sidebar of every ACP thread: <CR> opens one in its project, n starts a new one there"})
  (vim.api.nvim_create_user_command "AcpUsage" usage.open
    {:nargs "*" :complete usage.complete
     :desc "Show the account's usage: spend, tokens, models, activity, tools and limits; args are an optional agent, today|N|all and project"})
  (vim.api.nvim_create_user_command "AcpConfig" configure
    {:nargs "*" :complete (complete-settings 1)
     :desc "Show or change ACP session settings (model, mode, effort...)"})
  (vim.api.nvim_create_user_command "AcpSend" send
    {:nargs "*" :desc "Send the prompt buffer, or the given text, to the ACP agent"})
  (vim.api.nvim_create_user_command "AcpScreenshot" screenshot
    {:nargs "?" :complete (fn [] ["clipboard"])
     :desc "Add a screenshot to the ACP prompt: select one on screen after a few seconds (or N), or clipboard for the copied image"})
  (vim.api.nvim_create_user_command "AcpRun" #(handoff.run-shell $1 $1.args)
    {:nargs "+" :complete "shellcmdline"
     :desc "Run a shell command in a terminal and add its saved output to the ACP prompt"})
  (vim.api.nvim_create_user_command "AcpPath"
    #(handoff.link (if (= 0 (length $1.fargs)) ["%"] $1.fargs))
    {:nargs "*" :complete "file"
     :desc "Add the given files or directories, or the current file, to the ACP prompt"})
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
