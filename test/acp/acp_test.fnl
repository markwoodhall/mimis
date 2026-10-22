;; End-to-end tests for the ACP client against test/acp/fake_agent.py.
;; Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/acp_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(set vim.g.acp-agent-cmd ["python3" (.. here "/fake_agent.py")])
(set vim.g.acp-log-dir (vim.fn.tempname))

(local session (require :modules.acp.session))
(local failures [])

;; The fake agent's settings must not replace the real cache used for completion.
(local known-path (.. (vim.fn.stdpath :data) "/acp-config.json"))
(local known-backup (when (= 1 (vim.fn.filereadable known-path)) (vim.fn.readfile known-path)))
(vim.fn.delete known-path)

(fn out [line]
  (io.stdout:write (.. line "\n")))

(fn check [name ok detail]
  (if ok
    (out (.. "ok   " name))
    (do
      (table.insert failures name)
      (out (.. "FAIL " name (if detail (.. "\n     " (vim.inspect detail)) ""))))))

(fn wait [pred ms]
  (vim.wait (or ms 3000) pred 10))

(fn lines-of [buf]
  (vim.api.nvim_buf_get_lines buf 0 -1 false))

(fn has-line [lines text]
  (accumulate [found false _ l (ipairs lines)]
    (or found (= l text))))

(fn statusline-of [win]
  (. (vim.api.nvim_eval_statusline vim.o.statusline {:winid win}) :str))

(fn select-first []
  (set vim.ui.select (fn [items _ cb] (vim.schedule #(cb (. items 1))))))

(fn select-never []
  (set vim.ui.select (fn [])))

;; Before a session ------------------------------------------------------------

(vim.cmd "AcpSend too early")
(check "AcpSend without a session is refused" (= nil (session.current)))

(local start-win (vim.api.nvim_get_current_win))
(vim.cmd "tab Acp")
(local s (session.current))
(check ":tab Acp opens in a new tab" (= 2 (vim.fn.tabpagenr)))
(check "chat and prompt buffers are unlisted"
       (and (= 0 (vim.fn.buflisted s.buf)) (= 0 (vim.fn.buflisted s.prompt-buf))))

;; :Acp brings a hidden session back
(fn windows-showing [buf]
  (length (vim.fn.win_findbuf buf)))

(vim.cmd "only")
(vim.cmd "Acp")
(check ":Acp shows the chat again after :only in the prompt"
       (and (= 1 (windows-showing s.buf)) (= 1 (windows-showing s.prompt-buf))))
(vim.cmd "enew")
(vim.cmd "only")
(vim.cmd "Acp")
(check ":Acp shows a fully hidden session again"
       (and (= 1 (windows-showing s.buf)) (= 1 (windows-showing s.prompt-buf))))
(check "activity shows while starting" (not= nil (string.find (session.status-text) "starting agent" 1 true)))

(wait #(not= nil s.session.id))
(check "session connects" (= "sess-1" s.session.id))

;; Config options ----------------------------------------------------------------

(let [model (session.config-option s :model)
      mode (session.config-option s :mode)]
  (check "boolean config options are ignored" (= 2 (length (session.config s))) (session.config s))
  (check "grouped values are flattened" (= 2 (length model.values)))
  (check "a Default value shows what it resolves to" (= "Opus 5.5" model.display))
  (check "mode is shown by name" (= "Manual" mode.display)))

(check "connected line lists the settings"
       (has-line (lines-of s.buf) "> acp: Mode: Manual · Model: Opus 5.5"))

(let [prompt-win (vim.fn.bufwinid s.prompt-buf)]
  (check "statusline in session windows shows model and mode"
         (not= nil (string.find (statusline-of prompt-win) "[acp Opus 5.5 · Manual]" 1 true))
         (statusline-of prompt-win))
  (check "statusline elsewhere is quiet while idle"
         (= nil (string.find (statusline-of start-win) "acp" 1 true))
         (statusline-of start-win)))

(check "AcpConfig completes setting names"
       (vim.deep_equal ["mode" "model"] (vim.fn.getcompletion "AcpConfig " "cmdline"))
       (vim.fn.getcompletion "AcpConfig " "cmdline"))
(check "AcpConfig completes values"
       (vim.deep_equal ["default" "sonnet"] (vim.fn.getcompletion "AcpConfig model " "cmdline")))

(vim.cmd "AcpConfig model nonsense")
(vim.wait 200)
(check "unknown values are rejected" (= "default" (. (session.config-option s :model) :current)))

(vim.cmd "AcpConfig model sonnet")
(wait #(= "sonnet" (. (session.config-option s :model) :current)))
(check "AcpConfig sets a value" (= "Sonnet 5.5" (. (session.config-option s :model) :display)))
(check "the change is noted in the chat" (has-line (lines-of s.buf) "> acp: Model → Sonnet 5.5"))

;; A full turn: streaming, tools, permission, unknown request ---------------------

(select-first)
(vim.api.nvim_set_current_win (vim.fn.bufwinid s.prompt-buf))
(vim.api.nvim_buf_set_lines s.prompt-buf 0 -1 false ["hello there" "second line"])
(vim.cmd "stopinsert")
(vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false)
(check "<CR> in normal mode sends and clears the prompt" (vim.deep_equal [""] (lines-of s.prompt-buf)))
(wait #(and (= s.turn.state :idle) (not= nil s.log.path)))

(let [chat (lines-of s.buf)]
  (check "reply streams in across split JSON lines" (has-line chat "You said: hello there"))
  (check "tool lines are rewritten in place" (has-line chat "> tool: Read /tmp/x/file.clj — done"))
  (check "permission choice is recorded" (has-line chat "> permission: Edit file.clj — Allow once"))
  (check "stop reason is shown" (has-line chat "> stop: end_turn"))
  (check "thinking streams in as >> lines"
         (and (has-line chat ">> hmm") (has-line chat ">> let me think")) chat)
  (check "a blank line separates thinking from the reply"
         (let [i (accumulate [at nil i l (ipairs chat) &until at] (when (= l ">> let me think") i))]
           (and i (= "" (. chat (+ i 1))) (= "You said: hello there" (. chat (+ i 2)))))))

(let [win (vim.fn.bufwinid s.buf)
      row (accumulate [at nil i l (ipairs (lines-of s.buf)) &until at] (when (= l ">> hmm") i))]
  (check "thinking is folded closed in the chat"
         (and row (not= -1 (vim.api.nvim_win_call win #(vim.fn.foldclosed row)))))
  (check "the reply is not folded"
         (= -1 (vim.api.nvim_win_call win #(vim.fn.foldclosed (+ row 3))))))

;; Tool details -------------------------------------------------------------------

(fn row-of [line]
  (accumulate [at nil i l (ipairs (lines-of s.buf)) &until at] (when (= l line) i)))

(fn press-enter-on [row]
  (vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
  (vim.api.nvim_win_set_cursor 0 [row 0])
  (vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false))

(fn lines-after [row n]
  (vim.api.nvim_buf_get_lines s.buf row (+ row n) false))

(local before-expanding (lines-of s.buf))
(local edit-row (row-of "> tool: Edit file.clj — done"))
(local read-row (row-of "> tool: Read /tmp/x/file.clj — done"))

;; Read is directly above Edit, so expanding it also checks Edit's line moves with it.
(press-enter-on read-row)
(let [read (lines-after read-row 14)]
  (check "<CR> on a tool line expands it inline" (= "" (. read 1)) read)
  (check "expanded details show the input as JSON"
         (and (has-line read "#### Input") (has-line read "  \"file_path\": \"/tmp/x/file.clj\"")) read)
  (check "expanded details strip terminal colours" (has-line read "(ns x)") read))

(local edit-row-now (row-of "> tool: Edit file.clj — done"))
(check "lines below an expansion move down with it" (> edit-row-now edit-row))
(vim.api.nvim_win_set_cursor 0 [edit-row-now 0])
(vim.cmd "AcpTool")
(check ":AcpTool on a tool line works like <CR>"
       (= "#### Files" (. (lines-after edit-row-now 2) 2))
       (lines-after edit-row-now 2))
(let [edit (lines-after edit-row-now 22)]
  (check "diff headers for files outside the project have no a/ prefix"
         (has-line edit "--- /tmp/x/file.clj") edit)
  (check "expanded edits list files with line numbers" (has-line edit "/tmp/x/file.clj:2") edit)
  (check "expanded edits show a unified diff"
         (and (has-line edit "```diff") (has-line edit "-(def a 1)") (has-line edit "+(def a 2)")) edit)
  (check "expanded edits leave out input that repeats the diff" (not (has-line edit "#### Input")) edit)
  (check "expanded edits show the output" (has-line edit "The file /tmp/x/file.clj has been updated.") edit))

;; <CR> inside an expansion collapses it
(press-enter-on (+ edit-row-now 3))
(press-enter-on read-row)
(check "<CR> again collapses, leaving the chat as it was"
       (vim.deep_equal before-expanding (lines-of s.buf)))

(vim.api.nvim_win_set_cursor 0 [1 0])
(vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false)
(check "<CR> elsewhere in the chat moves down as usual"
       (= 2 (. (vim.api.nvim_win_get_cursor 0) 1)))

(press-enter-on edit-row)
(session.send-prompt s "plain")
(wait #(= s.turn.state :idle))
(let [log (vim.fn.readfile s.log.path)]
  (check "a turn finishing while expanded is logged" (has-line log "Plain reply.") log)
  (check "expanded details never reach the log" (not (has-line log "#### Files")) log))
(press-enter-on edit-row)
(check "a tool still collapses after more turns" (not (has-line (lines-of s.buf) "#### Files")))

;; Expanded while running: the line and details update in place when it finishes
(var pending-choice nil)
(set vim.ui.select (fn [items _ cb] (set pending-choice #(cb (. items 1)))))
(session.send-prompt s "expand while running")
(wait #(not= nil s.permission))
(local running-row
  (accumulate [at nil i l (ipairs (lines-of s.buf))]
    (if (= l "> tool: Edit file.clj — pending") i at)))
(press-enter-on running-row)
(check "a running tool expands" (= "#### Files" (. (lines-after running-row 2) 2)) (lines-after running-row 3))
(pending-choice)
(wait #(= s.turn.state :idle))
(let [after (lines-after (- running-row 1) 24)]
  (check "a finished tool's line updates in place while expanded"
         (= "> tool: Edit file.clj — done" (. after 1)) after)
  (check "an expanded tool's details refresh when it finishes"
         (has-line after "The file /tmp/x/file.clj has been updated.") after))
(press-enter-on running-row)
(check "a refreshed expansion collapses cleanly" (not (has-line (lines-of s.buf) "#### Files")))
(select-first)

(vim.api.nvim_set_current_win start-win)
(vim.cmd "AcpTool")
(check "AcpTool elsewhere shows the latest tool call" (= "# Edit file.clj — done" (vim.api.nvim_get_current_line)))
(vim.cmd "close")
(vim.api.nvim_set_current_win (. (vim.fn.win_findbuf s.prompt-buf) 1))

(let [log (vim.fn.readfile s.log.path)]
  (check "thinking is kept in the log" (has-line log ">> let me think") log))

(check "context use shows in the statusline"
       (not= nil (string.find (statusline-of (vim.fn.bufwinid s.prompt-buf)) "Sonnet 5.5 · Manual · 25%" 1 true))
       (statusline-of (vim.fn.bufwinid s.prompt-buf)))

(let [log (vim.fn.readfile s.log.path)]
  (check "log header records the settings" (and (has-line log "model: Sonnet 5.5") (has-line log "mode: Manual")) log)
  (check "log header records the session" (has-line log "session: sess-1"))
  (check "log has the turn" (and (has-line log "## Agent") (has-line log "> tool: Edit file.clj — done"))))

;; Cancel with a permission prompt left open ---------------------------------------

(select-never)
(session.send-prompt s "slow")
(wait #(not= nil s.permission))
(vim.wait 200)
(check "activity shows a waiting permission" (= "waiting for your permission" (?. s.activity :label)))
(vim.cmd "AcpCancel")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "cancel answers the open permission" (has-line chat "> permission: Run `rm -rf build` — cancelled"))
  (check "cancel ends the turn" (has-line chat "> stop: cancelled")))
(check "activity clears after cancel" (and (= nil s.activity) (= nil s.activity-timer)))

;; Settings changed between turns and by the agent ------------------------------------

(select-first)
(vim.cmd "AcpConfig mode plan")
(wait #(= "plan" (. (session.config-option s :mode) :current)))
(session.send-prompt s "leave plan")
(wait #(= s.turn.state :idle))
(check "agent-initiated changes are applied" (= "Manual" (. (session.config-option s :mode) :display)))
(let [log (vim.fn.readfile s.log.path)]
  (check "a change between turns is logged" (has-line log "> acp: Mode → Plan") log)
  (check "a change during a turn is logged" (has-line log "> acp: Mode → Manual") log))

;; Commands ------------------------------------------------------------------------

(vim.api.nvim_buf_set_lines s.prompt-buf 0 -1 false ["draft"])
(vim.cmd "AcpSend from the command line")
(wait #(= s.turn.state :idle))
(check "AcpSend <text> leaves the draft alone" (vim.deep_equal ["draft"] (lines-of s.prompt-buf)))
(check "AcpSend <text> sends the text" (has-line (lines-of s.buf) "You said: from the command line"))

(vim.cmd "wa")
(vim.wait 200)
(check ":wa does not send the prompt" (vim.deep_equal ["draft"] (lines-of s.prompt-buf)))

(vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
(each [i l (ipairs (lines-of s.buf))]
  (when (= l "(+ 1 2)") (vim.api.nvim_win_set_cursor 0 [i 0])))
(vim.cmd "AcpOpenBlock")
(check "AcpOpenBlock opens the block with its filetype"
       (and (= "clojure" vim.bo.filetype) (= "(+ 1 2)" (vim.api.nvim_get_current_line))))
(vim.cmd "close")

(vim.api.nvim_set_current_win (vim.fn.bufwinid s.prompt-buf))
(vim.api.nvim_feedkeys (.. "o" (vim.keycode "<CR>") "more" (vim.keycode "<Esc>")) :x false)
(check "<CR> in insert mode is still a newline" (vim.deep_equal ["draft" "" "more"] (lines-of s.prompt-buf))
       (lines-of s.prompt-buf))

;; Starting with settings -----------------------------------------------------------

(vim.cmd "Acp model")
(check "unpaired settings are refused" (= s (session.current)))

(vim.cmd "Acp mode plan")
(wait #(= "plan" (. (session.config-option s :mode) :current)))
(check ":Acp with settings changes the running session" (= s (session.current)))
(check ":Acp with settings notes the change" (has-line (lines-of s.buf) "> acp: Mode → Plan"))

(set vim.g.acp-config {:mode "plan" :model "nonsense"})
(vim.cmd "Acp! model sonnet")
(local s2 (session.current))
(check ":Acp! starts a new session" (and (not= s s2) (not (vim.api.nvim_buf_is_valid s.buf))))
(check "prompts wait until settings are applied" (not (session.send-prompt s2 "too soon")))
(wait #s2.ready)
(check "arguments override vim.g.acp-config" (= "sonnet" (. (session.config-option s2 :model) :current)))
(check "vim.g.acp-config applies to new sessions" (= "plan" (. (session.config-option s2 :mode) :current)))
(check "starting settings are not noted as changes"
       (not (has-line (lines-of s2.buf) "> acp: Model → Sonnet 5.5")))
(check "connected line shows the applied settings"
       (has-line (lines-of s2.buf) "> acp: Mode: Plan · Model: Sonnet 5.5")
       (lines-of s2.buf))
(set vim.g.acp-config nil)

(vim.cmd "Acp! model nonsense")
(local s3 (session.current))
(wait #s3.ready)
(check "bad starting values are reported, not fatal"
       (and s3.ready (has-line (lines-of s3.buf) "> acp: nonsense is not a value of model"))
       (lines-of s3.buf))

(local chat-buf s3.buf)
(vim.cmd "AcpStop")
(check "AcpStop ends the session" (= nil (session.current)))
(check "AcpStop removes the buffers" (not (vim.api.nvim_buf_is_valid chat-buf)))

(check ":Acp completes settings from the last session"
       (vim.deep_equal ["mode" "model"] (vim.fn.getcompletion "Acp " "cmdline")))
(check ":Acp completes values from the last session"
       (vim.deep_equal ["default" "sonnet"] (vim.fn.getcompletion "Acp mode plan model " "cmdline")))
(check ":Acp doesn't offer settings already given"
       (vim.deep_equal ["model"] (vim.fn.getcompletion "Acp mode plan " "cmdline"))
       (vim.fn.getcompletion "Acp mode plan " "cmdline"))
(check ":AcpConfig completes only one pair"
       (vim.deep_equal [] (vim.fn.getcompletion "AcpConfig mode plan " "cmdline")))

;; Killing Neovim mid-turn keeps every completed turn ---------------------------------

(let [marker (vim.fn.tempname)
      child-log-dir (vim.fn.tempname)
      child (vim.system ["nvim" "--headless" "-c"
                         (.. "lua require('fennel').dofile('" here "/kill_child.fnl')")]
                        {:env {:ACP_TEST_MARKER marker :ACP_TEST_LOG_DIR child-log-dir}})]
  (wait #(= 1 (vim.fn.filereadable marker)) 15000)
  (child:kill :sigkill)
  (child:wait 5000)
  (let [log-path (?. (vim.fn.readfile marker) 1)
        log (if log-path (vim.fn.readfile log-path) [])]
    (check "a killed session keeps its completed turns"
           (and (has-line log "completed turn") (has-line log "You said: completed turn")) log)
    (check "a killed session drops the unfinished turn" (not (has-line log "slow")) log))
  (vim.fn.delete marker)
  (vim.fn.delete child-log-dir "rf"))

(vim.fn.delete vim.g.acp-log-dir "rf")
(if known-backup
  (vim.fn.writefile known-backup known-path)
  (vim.fn.delete known-path))
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
