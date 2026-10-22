;; End-to-end tests for the ACP client against test/acp/fake_agent.py.
;; Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/acp_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(set vim.g.acp-agent-cmd ["python3" (.. here "/fake_agent.py")])
(set vim.g.acp-log-dir (vim.fn.tempname))
;; Keep test traffic out of the real debug log and settings cache, even if a run aborts.
(set vim.g.acp-debug-log (vim.fn.tempname))
(set vim.g.acp-config-cache (vim.fn.tempname))
(local real-debug-log (.. (vim.fn.stdpath :log) "/acp-debug.log"))
(local real-debug-size (vim.fn.getfsize real-debug-log))
(local real-cache (.. (vim.fn.stdpath :data) "/acp-config.json"))
(local real-cache-before (when (= 1 (vim.fn.filereadable real-cache)) (vim.fn.readfile real-cache)))

(local session (require :modules.acp.session))
(local failures [])

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

;; While auto-allow is on, permission requests are answered with :AcpAllow.
(var auto-allow true)
(local auto-timer (vim.uv.new_timer))
(auto-timer:start 20 20 (vim.schedule_wrap
                          (fn []
                            (let [current (session.current)]
                              (when (and auto-allow current current.permission)
                                (vim.cmd "AcpAllow"))))))

;; Before a session ------------------------------------------------------------

(vim.cmd "AcpSend too early")
(check "AcpSend without a session is refused" (= nil (session.current)))

(local start-win (vim.api.nvim_get_current_win))
(vim.cmd "tab Acp")
(local s (session.current))
(check ":tab Acp opens in a new tab" (= 2 (vim.fn.tabpagenr)))
(check "the chat buffer is unlisted" (= 0 (vim.fn.buflisted s.buf)))
(check "there is just one buffer, the chat"
       (= 1 (length (vim.tbl_filter #(vim.startswith (vim.api.nvim_buf_get_name $1) "acp://")
                                    (vim.api.nvim_list_bufs)))))

;; The input area at the bottom of the chat
(local render (require :modules.acp.render))

(fn input-lines []
  (vim.api.nvim_buf_get_lines s.buf (- (render.input-row s) 1) -1 false))

(fn set-input [lines]
  (vim.api.nvim_buf_set_lines s.buf (- (render.input-row s) 1) -1 false lines))

(fn chat-win []
  (vim.fn.bufwinid s.buf))

(check "the chat ends with an input area"
       (vim.deep_equal ["" "## You" ""] (vim.list_slice (lines-of s.buf) (- (length (lines-of s.buf)) 2)))
       (lines-of s.buf))
(check ":Acp puts the cursor in the input area"
       (= (render.input-row s) (. (vim.api.nvim_win_get_cursor (chat-win)) 1)))

;; :Acp brings a hidden session back
(fn windows-showing [buf]
  (length (vim.fn.win_findbuf buf)))

(vim.cmd "enew")
(vim.cmd "only")
(vim.cmd "Acp")
(check ":Acp shows a hidden session again" (= 1 (windows-showing s.buf)))
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

(let [win (chat-win)]
  (check "statusline in the chat window shows model and mode"
         (not= nil (string.find (statusline-of win) "[acp Opus 5.5 · Manual]" 1 true))
         (statusline-of win))
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

(vim.api.nvim_set_current_win (chat-win))
(set-input ["hello there" "second line"])
(vim.api.nvim_win_set_cursor 0 [(render.input-row s) 0])
(vim.cmd "stopinsert")
(vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false)
(wait #(not= s.turn.state :idle) 1000)
(check "<CR> in the input area sends and clears it" (vim.deep_equal [""] (input-lines)) (input-lines))
(check "the cursor stays in the input area after sending"
       (= (render.input-row s) (. (vim.api.nvim_win_get_cursor 0) 1)))
(check "the sent prompt moves into the transcript, above the input area"
       (let [chat (lines-of s.buf)
             you (accumulate [at nil i l (ipairs chat)] (if (vim.startswith l "## You — ") i at))]
         (and you (= "hello there" (. chat (+ you 1))) (< you (- (render.input-row s) 2))))
       (lines-of s.buf))

;; Typing the next prompt while the reply streams in
(set-input ["next question"])
(wait #(and (= s.turn.state :idle) (not= nil s.log.path)))
(check "a draft typed during a reply is kept, below the reply"
       (and (vim.deep_equal ["next question"] (input-lines))
            (= "## You" (. (lines-of s.buf) (- (render.input-row s) 1))))
       (lines-of s.buf))
(check "the reply lands above the input area"
       (let [chat (lines-of s.buf)
             stop (accumulate [at nil i l (ipairs chat)] (if (= l "> stop: end_turn") i at))]
         (and stop (< stop (- (render.input-row s) 1)))))
(check "agent output can't be undone"
       (do
         (vim.api.nvim_set_current_win (chat-win))
         (vim.cmd "silent! undo")
         (has-line (lines-of s.buf) "You said: hello there"))
       (lines-of s.buf))
(set-input [""])

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
  (vim.api.nvim_set_current_win (. (vim.fn.win_findbuf s.buf) 1))
  (vim.api.nvim_win_set_cursor 0 [row 0])
  (vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false))

(fn lines-after [row n]
  (vim.api.nvim_buf_get_lines s.buf row (+ row n) false))

(local before-expanding (lines-of s.buf))
(local edit-row (row-of "> tool: Edit file.clj (+1 -1) — done"))
(local read-row (row-of "> tool: Read /tmp/x/file.clj — done"))

;; Read is directly above Edit, so expanding it also checks Edit's line moves with it.
(press-enter-on read-row)
(let [read (lines-after read-row 14)]
  (check "<CR> on a tool line expands it inline" (= "" (. read 1)) read)
  (check "expanded details show the input as JSON"
         (and (has-line read "#### Input") (has-line read "  \"file_path\": \"/tmp/x/file.clj\"")) read)
  (check "expanded details strip terminal colours" (has-line read "(ns x)") read))

(local edit-row-now (row-of "> tool: Edit file.clj (+1 -1) — done"))
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

;; Long tool titles are shortened, with the full title in the details
(session.send-prompt s "long titles")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)
      long-line (accumulate [at nil _ l (ipairs chat)]
                  (if (vim.startswith l "> tool: cd /tmp/x && echo step-0") l at))
      long-row (row-of long-line)]
  (check "long tool titles are cut to 72 characters"
         (and long-line (vim.endswith long-line "… — done")
              (= (+ 72 (vim.fn.strchars "> tool: " ) (vim.fn.strchars " — done")) (vim.fn.strchars long-line)))
         long-line)
  (check "multi-line titles show their first line and …"
         (has-line chat "> tool: cd /tmp/x && … — done") chat)
  (check "short titles are left alone" (has-line chat "> tool: ls — done"))
  (press-enter-on long-row)
  (let [details (lines-after long-row 5)]
    (check "expanded details start with the full title"
           (and (= "#### Title" (. details 2))
                (vim.endswith (. details 4) "echo step-19"))
           details))
  (press-enter-on long-row))

;; Permissions inline, and a tool expanded while it waits ---------------------------

(fn last-row-of [line]
  (accumulate [at nil i l (ipairs (lines-of s.buf))] (if (= l line) i at)))

(set auto-allow false)
(session.send-prompt s "expand while running")
(wait #(not= nil s.permission))
(local permission-row (last-row-of "> permission: Edit file.clj — awaiting choice"))
(let [under (lines-after permission-row 12)]
  (check "an edit's diff is shown under its permission request"
         (vim.deep_equal ["" "```diff" "--- /tmp/x/file.clj" "+++ /tmp/x/file.clj" "@@ -1,2 +1,2 @@"
                          " (ns x)" "-(def a 1)" "+(def a 2)" "```" ""]
                         (vim.list_slice under 1 10))
         under)
  (check "the choices follow the diff"
         (vim.deep_equal ["  1. Allow once" "  2. Reject"] (vim.list_slice under 11 12))
         under))
(vim.cmd "Acp")
(check ":Acp puts the cursor on the first choice, below the diff"
       (= "  1. Allow once" (vim.api.nvim_get_current_line))
       (vim.api.nvim_get_current_line))
(check "the statusline shows a waiting permission"
       (not= nil (string.find (session.status-text) "waiting for your permission" 1 true)))

(local running-row (last-row-of "> tool: Edit file.clj (+1 -1) — pending"))
(press-enter-on running-row)
(check "a running tool expands" (= "#### Files" (. (lines-after running-row 2) 2)) (lines-after running-row 3))

(press-enter-on (last-row-of "> permission: Edit file.clj — awaiting choice"))
(check "<CR> on the request itself doesn't answer it" (not= nil s.permission))
(check "<CR> on the request leaves the tool expanded" (= "#### Files" (. (lines-after running-row 2) 2)))
(press-enter-on (+ (last-row-of "> permission: Edit file.clj — awaiting choice") 3))
(check "<CR> inside the diff doesn't answer" (not= nil s.permission))
(press-enter-on (session.first-choice-row s))
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "<CR> on a choice answers it" (has-line chat "> permission: Edit file.clj — Allow once"))
  (check "the choices go once answered" (not (has-line chat "  1. Allow once")) chat))
(let [log (vim.fn.readfile s.log.path)]
  (check "the log has the answer, not the choices"
         (and (has-line log "> permission: Edit file.clj — Allow once") (not (has-line log "  2. Reject"))) log))
(let [after (lines-after (- running-row 1) 24)]
  (check "a finished tool's line updates in place while expanded"
         (= "> tool: Edit file.clj (+1 -1) — done" (. after 1)) after)
  (check "an expanded tool's details refresh when it finishes"
         (has-line after "The file /tmp/x/file.clj has been updated.") after))
(press-enter-on running-row)
(check "a refreshed expansion collapses cleanly" (not (has-line (lines-of s.buf) "#### Files")))

(session.send-prompt s "reject this one")
(wait #(not= nil s.permission))
(vim.api.nvim_set_current_win start-win)
(vim.cmd "AcpReject")
(wait #(= s.turn.state :idle))
(check ":AcpReject answers from another window"
       (has-line (lines-of s.buf) "> permission: Edit file.clj — Reject"))
(check "a rejected tool shows as failed" (has-line (lines-of s.buf) "> tool: Edit file.clj (+1 -1) — failed"))

(session.send-prompt s "always allow")
(wait #(not= nil s.permission))
(vim.cmd "AcpAllow!")
(wait #(= s.turn.state :idle))
(let [last-permission (accumulate [at nil _ l (ipairs (lines-of s.buf))]
                        (if (vim.startswith l "> permission:") l at))]
  (check ":AcpAllow! falls back to allow once when always isn't offered"
         (= "> permission: Edit file.clj — Allow once" last-permission) last-permission))
(vim.cmd "AcpAllow")
(check ":AcpAllow with nothing waiting is harmless" (= s.turn.state :idle))

(session.send-prompt s "long command")
(wait #(not= nil s.permission))
(let [row (render.line-row s s.permission.block)
      under (vim.api.nvim_buf_get_lines s.buf row (+ row 6) false)]
  (check "a shortened command is shown in full under its permission request"
         (and (= "```sh" (. under 2)) (vim.endswith (. under 3) "echo step-19") (= "  1. Yes" (. under 6)))
         under))
(vim.cmd "AcpReject")
(wait #(= s.turn.state :idle))

(session.send-prompt s "big edit")
(wait #(not= nil s.permission))
(let [row (render.line-row s s.permission.block)
      under (vim.api.nvim_buf_get_lines s.buf row (+ row 90) false)]
  (check "a large diff is capped under the permission request"
         (and (has-line under "… 123 more lines, <CR> on the tool line shows them all")
              (has-line under "  1. Yes")
              (not (has-line under "+line 199")))
         under))
(check "a new file's tool line shows its size" (has-line (lines-of s.buf) "> tool: Write big.txt (+200 -0) — pending"))
(vim.cmd "AcpAllow")
(wait #(= s.turn.state :idle))
(let [row (last-row-of "> tool: Write big.txt (+200 -0) — done")]
  (press-enter-on row)
  (check "the tool's expansion shows the whole diff" (has-line (lines-of s.buf) "+line 199"))
  (press-enter-on row))
(set auto-allow true)

(vim.api.nvim_set_current_win start-win)
(vim.cmd "AcpTool")
(check "AcpTool elsewhere shows the latest tool call" (= "# Write big.txt — done" (vim.api.nvim_get_current_line)))
(vim.cmd "close")
(vim.api.nvim_set_current_win (. (vim.fn.win_findbuf s.buf) 1))

(let [log (vim.fn.readfile s.log.path)]
  (check "thinking is kept in the log" (has-line log ">> let me think") log))

(check "context use shows in the statusline"
       (not= nil (string.find (statusline-of (chat-win)) "Sonnet 5.5 · Manual · 25%" 1 true))
       (statusline-of (chat-win)))

(let [log (vim.fn.readfile s.log.path)]
  (check "log header records the settings" (and (has-line log "model: Sonnet 5.5") (has-line log "mode: Manual")) log)
  (check "log header records the session" (has-line log "session: sess-1"))
  (check "log has the turn" (and (has-line log "## Agent") (has-line log "> tool: Edit file.clj (+1 -1) — done"))))

;; Cancel with a permission prompt left open ---------------------------------------

(set auto-allow false)
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

(set auto-allow true)
(vim.cmd "AcpConfig mode plan")
(wait #(= "plan" (. (session.config-option s :mode) :current)))
(session.send-prompt s "leave plan")
(wait #(= s.turn.state :idle))
(check "agent-initiated changes are applied" (= "Manual" (. (session.config-option s :mode) :display)))
(let [log (vim.fn.readfile s.log.path)]
  (check "a change between turns is logged" (has-line log "> acp: Mode → Plan") log)
  (check "a change during a turn is logged" (has-line log "> acp: Mode → Manual") log))

;; Commands ------------------------------------------------------------------------

(set-input ["draft"])
(vim.cmd "AcpSend from the command line")
(wait #(= s.turn.state :idle))
(check "AcpSend <text> leaves the draft alone" (vim.deep_equal ["draft"] (input-lines)))
(check "AcpSend <text> sends the text" (has-line (lines-of s.buf) "You said: from the command line"))

(vim.cmd "wa")
(vim.wait 200)
(check ":wa does not send the prompt" (vim.deep_equal ["draft"] (input-lines)))

(vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
(each [i l (ipairs (lines-of s.buf))]
  (when (= l "(+ 1 2)") (vim.api.nvim_win_set_cursor 0 [i 0])))
(vim.cmd "AcpOpenBlock")
(check "AcpOpenBlock opens the block with its filetype"
       (and (= "clojure" vim.bo.filetype) (= "(+ 1 2)" (vim.api.nvim_get_current_line))))
(vim.cmd "close")

(vim.api.nvim_set_current_win (chat-win))
(vim.api.nvim_win_set_cursor 0 [(render.input-row s) 0])
(vim.api.nvim_feedkeys (.. "o" (vim.keycode "<CR>") "more" (vim.keycode "<Esc>")) :x false)
(check "<CR> in insert mode is still a newline" (vim.deep_equal ["draft" "" "more"] (input-lines))
       (input-lines))

(vim.cmd "AcpSend")
(wait #(= s.turn.state :idle))
(check ":AcpSend sends the input area and clears it"
       (and (vim.deep_equal [""] (input-lines)) (has-line (lines-of s.buf) "You said: draft")))

(vim.api.nvim_set_current_win start-win)
(vim.cmd "Acp")
(check ":Acp from elsewhere focuses the chat's input area"
       (and (= (vim.api.nvim_get_current_buf) s.buf)
            (= (render.input-row s) (. (vim.api.nvim_win_get_cursor 0) 1))))

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
                        {:env {:ACP_TEST_MARKER marker
                               :ACP_TEST_LOG_DIR child-log-dir
                               :ACP_TEST_DEBUG_LOG vim.g.acp-debug-log
                               :ACP_TEST_CONFIG_CACHE vim.g.acp-config-cache}})]
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

;; Debug log ------------------------------------------------------------------------

(let [debug-lines (vim.fn.readfile vim.g.acp-debug-log)
      tag (.. " [" (vim.fn.getpid) "] ")
      pids (collect [_ l (ipairs debug-lines)]
             (let [p (string.match l "^%d%d:%d%d:%d%d %[(%d+)%] ")]
               (when p (values p true))))]
  (check "debug traffic goes to vim.g.acp-debug-log" (> (length debug-lines) 0))
  (check "every debug line carries a process id"
         (accumulate [ok true _ l (ipairs debug-lines)]
           (and ok (not= nil (string.match l "^%d%d:%d%d:%d%d %[%d+%] "))))
         (. debug-lines 1))
  (check "two Neovims sharing a log are told apart (this one and the killed child)"
         (and (. pids (tostring (vim.fn.getpid))) (= 2 (length (vim.tbl_keys pids))))
         (vim.tbl_keys pids))
  (check "the real debug log has nothing from the tests"
         (or (= -1 real-debug-size)
             (accumulate [clean true _ l (ipairs (vim.fn.readfile real-debug-log))]
               (and clean (= nil (string.find l tag 1 true)))))))
(vim.fn.delete vim.g.acp-debug-log)

(vim.fn.delete vim.g.acp-log-dir "rf")
(check "the real settings cache is left alone"
       (vim.deep_equal real-cache-before
                       (when (= 1 (vim.fn.filereadable real-cache)) (vim.fn.readfile real-cache))))
(vim.fn.delete vim.g.acp-config-cache)
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
