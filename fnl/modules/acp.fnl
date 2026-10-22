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

(fn open [opts]
  (let [s (session.current)
        mods (?. opts :mods)]
    (if (session.alive? s)
      (render.show s mods)
      (let [_ (when s (session.stop s))
            s (session.start)]
        (vim.keymap.set [:n :i] "<C-s>" send {:buffer s.prompt-buf :desc "ACP send prompt"})
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
          (let [known (accumulate [ok false _ v (ipairs option.values)]
                        (or ok (= v.value value)))]
            (if known
              (session.set-config s id value)
              (vim.notify (.. "acp: " value " is not a value of " id) vim.log.levels.WARN))))))))

(fn complete-config [arglead cmdline _]
  (let [s (session.current)
        args (. (vim.api.nvim_parse_cmd cmdline {}) :args)
        done (if (= arglead "") (length args) (- (length args) 1))
        candidates (if (= done 0)
                     (icollect [_ o (ipairs (session.config s))] o.id)
                     (= done 1)
                     (let [option (session.config-option s (. args 1))]
                       (icollect [_ v (ipairs (or (?. option :values) []))] v.value))
                     [])]
    (icollect [_ c (ipairs candidates)]
      (when (vim.startswith c arglead) c))))

(fn enable [])

(fn setup []
  (when (not vim.g.markdown_fenced_languages)
    (set vim.g.markdown_fenced_languages
         [:clojure :fennel :sh :bash=sh :diff :json :lua :sql :python]))

  (vim.api.nvim_create_user_command "Acp" open {:desc "Open or focus the ACP agent session"})
  (vim.api.nvim_create_user_command "AcpConfig" configure
    {:nargs "*" :complete complete-config
     :desc "Show or change ACP session settings (model, mode, effort...)"})
  (vim.api.nvim_create_user_command "AcpSend" send
    {:nargs "*" :desc "Send the prompt buffer, or the given text, to the ACP agent"})
  (vim.api.nvim_create_user_command "AcpCancel" cancel {:desc "Cancel the running ACP turn"})
  (vim.api.nvim_create_user_command "AcpStop" quit {:desc "End the ACP session"})
  (vim.api.nvim_create_user_command "AcpOpenBlock" render.open-code-block
    {:desc "Open the fenced code block under the cursor in its own buffer"})
  (vim.api.nvim_create_user_command
    "AcpGrep"
    (fn [opts]
      (vim.cmd (.. "silent grep! " (vim.fn.shellescape opts.args 1) " " (vim.fn.fnameescape (log.log-dir)))))
    {:nargs "+" :desc "Search ACP session logs"}))

{: enable
 : setup}
