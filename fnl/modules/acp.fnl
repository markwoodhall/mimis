;; ACP client: user commands. See fnl/modules/acp/ for the pieces.

(local session (require :modules.acp.session))
(local render (require :modules.acp.render))
(local log (require :modules.acp.log))

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
  ;; ["model" "sonnet" "mode" "plan"] -> {:model "sonnet" :mode "plan"}, or nil if unpaired.
  (when (= 0 (% (length fargs) 2))
    (let [requested {}]
      (for [i 1 (length fargs) 2]
        (tset requested (. fargs i) (. fargs (+ i 1))))
      requested)))

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
  (vim.keymap.set :n "<CR>"
                  (fn []
                    (if (session.tool-at s (chat-row s)) "<Cmd>AcpTool<CR>" "<CR>"))
                  {:buffer s.buf :expr true :desc "ACP toggle tool details"}))

(fn open [opts]
  ;; :Acp [setting value]...  open or focus the session, changing any settings given
  ;; :Acp! [setting value]... end the current session and start a new one
  ;; New sessions start from vim.g.acp-config, with the arguments on top.
  (let [s (session.current)
        mods opts.mods
        requested (setting-pairs opts.fargs)]
    (if (not requested)
      (vim.notify "acp: settings come in pairs, e.g. :Acp model sonnet mode plan" vim.log.levels.WARN)
      (and (session.alive? s) (not opts.bang))
      (do
        (when (next requested)
          (session.configure s requested))
        (render.show s mods))
      (let [_ (when s (session.stop s))
            s (session.start (vim.tbl_extend :force (or vim.g.acp-config {}) requested))]
        (vim.keymap.set :n "<CR>" send {:buffer s.prompt-buf :desc "ACP send prompt"})
        (chat-keymaps s)
        (render.show s mods)))))

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

(fn complete-settings [max-pairs]
  ;; Completes "setting value" pairs, from the running session or the last one seen.
  (fn [arglead cmdline _]
    (let [known (session.known-config)
          args (. (vim.api.nvim_parse_cmd cmdline {}) :args)
          done (if (= arglead "") (length args) (- (length args) 1))
          candidates (if (>= done (* 2 max-pairs))
                       []
                       (= 0 (% done 2))
                       (let [given (collect [i a (ipairs args)]
                                     (when (and (<= i done) (= 1 (% i 2))) (values a true)))]
                         (icollect [_ o (ipairs known)]
                           (when (not (. given o.id)) o.id)))
                       (let [id (. args done)]
                         (accumulate [choices [] _ o (ipairs known)]
                           (if (= o.id id) o.values choices))))]
      (icollect [_ c (ipairs candidates)]
        (when (vim.startswith c arglead) c)))))

(fn enable [])

(fn setup []
  (when (not vim.g.markdown_fenced_languages)
    (set vim.g.markdown_fenced_languages
         [:clojure :fennel :sh :bash=sh :diff :json :lua :sql :python]))

  (vim.api.nvim_create_autocmd :VimLeavePre
    {:group (vim.api.nvim_create_augroup "acp" {:clear true})
     :desc "Stop the ACP agent"
     :callback #(session.shutdown)})

  (vim.api.nvim_create_user_command "Acp" open
    {:nargs "*" :bang true :complete (complete-settings 10)
     :desc "Open or focus the ACP session; ! starts a new one; args are setting/value pairs"})
  (vim.api.nvim_create_user_command "AcpConfig" configure
    {:nargs "*" :complete (complete-settings 1)
     :desc "Show or change ACP session settings (model, mode, effort...)"})
  (vim.api.nvim_create_user_command "AcpSend" send
    {:nargs "*" :desc "Send the prompt buffer, or the given text, to the ACP agent"})
  (vim.api.nvim_create_user_command "AcpCancel" cancel {:desc "Cancel the running ACP turn"})
  (vim.api.nvim_create_user_command "AcpStop" quit {:desc "End the ACP session"})
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
 : setup}
