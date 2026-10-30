;; End-to-end tests for the ACP client against test/acp/fake_agent.py.
;; Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/acp_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(set vim.g.acp-agent-cmd ["python3" (.. here "/fake_agent.py")])
;; The built-in opencode, replaced so tests never start the real one. claude keeps its
;; built-in profile, run with the fake agent through vim.g.acp-agent-cmd.
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})
;; The built-in opencode keeps its credits command, which runs the real opencode: off
;; except where the credits tests turn it on with a command of their own.
(set vim.g.acp-credits false)
(set vim.g.acp-log-dir (vim.fn.tempname))
;; Keep test traffic out of the real debug log and settings cache, even if a run aborts.
(set vim.g.acp-debug-log (vim.fn.tempname))
(set vim.g.acp-egress-log-dir (vim.fn.tempname))
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

(fn has-line [lines text pattern?]
  ;; text is literal unless pattern? is set, which passes it to string.find as a pattern.
  (accumulate [found false _ l (ipairs lines)]
    (or found (not= nil (string.find l text 1 (not pattern?))))))

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
  (check "statusline in the chat window shows agent, model and mode"
         (not= nil (string.find (statusline-of win) "[acp claude · Opus 5.5 · Manual]" 1 true))
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

;; Silence while a tool call is running -------------------------------------------------

(set vim.g.acp-stall-seconds 1)
(session.send-prompt s "stall")
(check "a silent turn is noted in the chat"
       (wait #(has-line (lines-of s.buf) "no update from 'Task explore: find the parser'") 5000)
       (lines-of s.buf))
(check "the activity label says how long it has been quiet"
       (and s.activity (has-line [s.activity.label] "no update for"))
       (?. s :activity))
(vim.cmd "AcpCancel")
(check "a silent turn can still be cancelled" (wait #(= s.turn.state :idle) 3000))
(check "the note stays after the turn" (has-line (lines-of s.buf) "— it may be waiting"))
(check "the stall timer is gone" (= nil s.stall-timer))
(set vim.g.acp-stall-seconds nil)

;; Updates the client doesn't understand ---------------------------------------------

(session.send-prompt s "unknown updates")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "an update of an unknown kind is reported"
         (has-line chat "ignored a 'subagent_progress' update") chat)
  (check "an update for another session is reported"
         (has-line chat "ignored updates for session other-session") chat)
  (check "another session's text never reaches the chat"
         (not (has-line chat "not this chat"))))
(session.send-prompt s "unknown updates")
(wait #(= s.turn.state :idle))
(check "each unknown kind is only reported once"
       (= 1 (length (vim.tbl_filter #(not= nil (string.find $1 "ignored a 'subagent_progress' update" 1 true)) (lines-of s.buf)))))

;; A turn that ends with a tool call still open -----------------------------------------

(session.send-prompt s "abandoned")
(wait #(= s.turn.state :idle))
(check "an unfinished tool call is named when the turn ends"
       (has-line (lines-of s.buf) "1 tool call never finished: Task explore: look around")
       (lines-of s.buf))

;; Parallel work and the sandbox marker in the statusline -------------------------------

(set vim.g.acp-stall-seconds 30)
(session.send-prompt s "background")
(wait #(has-line (lines-of s.buf) "> tool: Read notes.md — running"))
(vim.api.nvim_set_current_win (chat-win))
(let [status (statusline-of (chat-win))]
  (check "the statusline counts the tool running in the background"
         (not= nil (string.find status "1 bg" 1 true)) status)
  (check "the activity names the foreground tool, not the background one"
         (= "running Read notes.md" (?. s.activity :label))
         (?. s :activity)))
;; A background tool that stops reporting is caught while the foreground one is named.
(set vim.g.acp-stall-seconds 1)
(check "a quiet background tool is named, not just the newest one"
       (wait #(has-line (lines-of s.buf) "no update from 'Task explore: check the parser'") 5000)
       (lines-of s.buf))
(set s.sandbox {})
(check "the statusline says the session is sandboxed"
       (not= nil (string.find (session.status-text) "sandbox" 1 true))
       (session.status-text))
(set s.sandbox nil)
(check "an unsandboxed session has no sandbox marker"
       (= nil (string.find (session.status-text) "sandbox" 1 true)))
(vim.cmd "AcpCancel")
(wait #(= s.turn.state :idle))
(set vim.g.acp-stall-seconds nil)

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

;; Elicitation ------------------------------------------------------------------------

(local protocol (require :modules.acp.protocol))
(let [params (protocol.initialize-params)]
  (check "form elicitation is advertised at initialize"
         (not= nil (?. params :clientCapabilities :elicitation :form))
         params))

;; vim.ui prompts are stood in: each select or input takes the next planned answer.
(local original-ui-select vim.ui.select)
(local original-ui-input vim.ui.input)
(var select-plan [])
(var input-plan [])
(var ui-asks [])
(set vim.ui.select
     (fn [items opts on-choice]
       (table.insert ui-asks opts.prompt)
       (on-choice (when (> (length select-plan) 0)
                    (. items (table.remove select-plan 1))))))
(set vim.ui.input
     (fn [opts on-confirm]
       (table.insert ui-asks opts.prompt)
       (when (> (length input-plan) 0)
         (let [answer (table.remove input-plan 1)]
           (on-confirm (if (= answer :default) opts.default answer))))))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(local elic-row (last-row-of "> elicitation: Which strategy? — awaiting answer, <CR> to answer, :AcpDecline to decline"))
(let [under (lines-after elic-row 10)]
  (check "the question is asked in the chat with its fields"
         (vim.deep_equal ["Which strategy?" "And anything to note."
                          "" "  strategy (choice · required)"
                          "  1. conservative" "  2. balanced" "  3. aggressive"
                          "" "  notes (text · optional · default: as-is)" ""]
                         (vim.list_slice under 1 10))
         under))
(check "the statusline shows a waiting question"
       (not= nil (string.find (session.status-text) "waiting for your answer" 1 true))
       (session.status-text))

(set ui-asks [])
(set select-plan [3 3])
(set input-plan [:default])
(vim.cmd "AcpAnswer")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "the agent receives the answers" (has-line chat "Answered strategy=aggressive notes=as-is.") chat)
  (check "the answers are summarized on the block line"
         (has-line chat "> elicitation: Which strategy? — answered: strategy=aggressive, notes=as-is")
         chat)
  (check "the form goes once answered" (not (has-line chat "  1. conservative")) chat)
  (check "the input was prefilled with the default" (= "notes: " (. ui-asks 2)) ui-asks)
  (check "the review asks through the ui"
         (vim.deep_equal ["strategy: " "notes: " "Answers: "] ui-asks) ui-asks))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(vim.cmd "AcpDecline")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check ":AcpDecline declines without the walk"
         (and (has-line chat "> elicitation: Which strategy? — declined")
              (has-line chat "Declined."))
         chat))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(set select-plan [1 4])
(set input-plan [""])
(vim.cmd "AcpAnswer")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "an optional field left empty is left out, and review declines"
         (and (has-line chat "> elicitation: Which strategy? — declined")
              (has-line chat "Declined."))
         chat))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(set select-plan [1 3])
(set input-plan [:default])
(press-enter-on (last-row-of "> elicitation: Which strategy? — awaiting answer, <CR> to answer, :AcpDecline to decline"))
(wait #(= s.turn.state :idle))
(check "<CR> on the question line opens the form"
       (has-line (lines-of s.buf) "> elicitation: Which strategy? — answered: strategy=conservative, notes=as-is")
       (lines-of s.buf))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(set select-plan [])
(set input-plan [])
(vim.cmd "AcpAnswer")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "dismissing the form cancels the reply"
         (and (has-line chat "> elicitation: Which strategy? — cancelled")
              (has-line chat "Cancelled."))
         chat))

(session.send-prompt s "elicit")
(wait #(not= nil s.elicitation))
(vim.cmd "AcpCancel")
(wait #(= s.turn.state :idle))
(check "cancelling the turn answers the open question"
       (has-line (lines-of s.buf) "> elicitation: Which strategy? — cancelled")
       (lines-of s.buf))

(session.send-prompt s "elicit url")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "a url-mode question is refused as invalid params"
         (and (has-line chat "Could not ask: -32602.")
              (has-line chat "> acp: the agent asked for a url-mode interaction, which the client can't show"))
         chat))

(session.send-prompt s "elicit odd")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "a field type the client can't show is declined"
         (and (has-line chat "Declined.")
              (has-line chat "> acp: the agent asked about 'things', a field type the client can't show — declined"))
         chat))

(session.send-prompt s "elicit oneof")
(wait #(not= nil s.elicitation))
(let [under (lines-after (last-row-of "> elicitation: Questions — awaiting answer, <CR> to answer, :AcpDecline to decline") 12)]
  (check "oneOf options are shown as a choice, with the field's title"
         (vim.deep_equal ["Questions" ""
                          "  q0 — Failure (choice · optional)" "    What should happen on failure?"
                          "  1. Fail open — Let it through" "  2. Fail closed" ""
                          "  q0_custom — Failure (other) (text · optional)" "    Type your own answer"]
                         (vim.list_slice under 1 9))
         under))
(set ui-asks [])
(set select-plan [2 3])
(set input-plan [""])
(vim.cmd "AcpAnswer")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "a oneOf choice is answered with its const, and the custom field left out"
         (has-line chat "Answered {\"q0\": \"closed\"}.") chat)
  (check "the prompts carry the question, and optional choices can be skipped"
         (vim.deep_equal ["Failure — What should happen on failure?: "
                          "Failure (other) — Type your own answer: " "Answers: "]
                         ui-asks)
         ui-asks))

(session.send-prompt s "elicit multi")
(wait #(not= nil s.elicitation))
(let [under (lines-after (last-row-of "> elicitation: Pick several — awaiting answer, <CR> to answer, :AcpDecline to decline") 10)]
  (check "an array of options is shown as a multiple choice"
         (vim.deep_equal ["Pick several" ""
                          "  q1 — Flavours (choice, several · required)" "    Which flavours?"
                          "  1. Apple" "  2. Banana — Yellow" "  3. Cherry"]
                         (vim.list_slice under 1 7))
         under))
(set ui-asks [])
;; Done too early, tick three (one too many), Done, untick one, Done, then Submit.
(set select-plan [4 1 3 2 4 2 4 2])
(set input-plan [])
(vim.cmd "AcpAnswer")
(wait #(= s.turn.state :idle))
(let [chat (lines-of s.buf)]
  (check "a multiple choice is answered with an array, within its bounds"
         (has-line chat "Answered {\"q1\": [\"a\", \"c\"]}.") chat)
  (check "the chat shows the ticked options"
         (has-line chat "> elicitation: Pick several — answered: q1=a, c") chat))

(let [messages []]
  (let [original vim.notify]
    (set vim.notify (fn [msg] (table.insert messages msg)))
    (vim.cmd "AcpDecline")
    (set vim.notify original))
  (check "AcpDecline with nothing waiting says so"
         (accumulate [found false _ m (ipairs messages)]
           (or found (not= nil (string.find m "nothing is waiting for an answer" 1 true))))
         messages))

(set vim.ui.select original-ui-select)
(set vim.ui.input original-ui-input)

;; Floating pickers -------------------------------------------------------------------
;; With Neovim's own vim.ui in place the form's prompts open as floats.

(local ui (require :modules.acp.ui))
(fn float-count []
  (length (vim.tbl_filter #(not= "" (. (vim.api.nvim_win_get_config $1) :relative))
                          (vim.api.nvim_list_wins))))

(var picked :none)
(ui.select [{:name "a"} {:name "b"} {:name "c"}]
           {:prompt "Which? " :format_item #$1.name}
           (fn [item i] (set picked [(?. item :name) i])))
(check "a select opens a float" (= 1 (float-count)) (float-count))
(check "the float holds the question and the numbered choices"
       (vim.deep_equal ["Which?" "" "1. a" "2. b" "3. c"]
                       (vim.api.nvim_buf_get_lines 0 0 -1 false))
       (vim.api.nvim_buf_get_lines 0 0 -1 false))
(vim.api.nvim_feedkeys "2" :x false)
(wait #(not= picked :none))
(check "a number picks that choice and closes the float"
       (and (vim.deep_equal ["b" 2] picked) (= 0 (float-count)))
       [picked (float-count)])

(set picked :none)
(ui.select [{:name "a"} {:name "b"}] {:prompt "Which? " :format_item #$1.name}
           (fn [item i] (set picked [(?. item :name) i])))
(vim.api.nvim_feedkeys (vim.keycode "j<CR>") :x false)
(wait #(not= picked :none))
(check "<CR> picks the choice under the cursor" (vim.deep_equal ["b" 2] picked) picked)

(set picked :none)
(ui.select [{:name "a"} {:name "b"}] {:prompt "Which? " :format_item #$1.name}
           (fn [item i] (set picked [(?. item :name) i])))
(vim.api.nvim_feedkeys "q" :x false)
(wait #(not= picked :none))
(check "q cancels without a choice" (and (vim.deep_equal [nil nil] picked) (= 0 (float-count)))
       [picked (float-count)])

(var typed :none)
(ui.input {:prompt "Name: " :default "ab"} (fn [text] (set typed [text])))
(check "an input opens a float" (= 1 (float-count)) (float-count))
;; startinsert only takes effect back in the main loop, which a headless script never reaches.
(vim.api.nvim_feedkeys (.. (if (= :i (. (vim.api.nvim_get_mode) :mode)) "" "A")
                           "cd" (vim.keycode "<CR>")) :x false)
(wait #(not= typed :none))
(check "an input continues from its default" (and (vim.deep_equal ["abcd"] typed) (= 0 (float-count)))
       [typed (float-count)])

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

(check ":Acp completes settings and agents from the last session"
       (vim.deep_equal ["mode" "model" "claude" "opencode" "sandbox" "nosandbox"]
                       (vim.fn.getcompletion "Acp " "cmdline"))
       (vim.fn.getcompletion "Acp " "cmdline"))
(check ":Acp completes agents and settings after a sandbox switch"
       (vim.deep_equal ["mode" "model" "claude" "opencode"]
                       (vim.fn.getcompletion "Acp sandbox " "cmdline"))
       (vim.fn.getcompletion "Acp sandbox " "cmdline"))
(check ":Acp completes values from the last session"
       (vim.deep_equal ["default" "sonnet"] (vim.fn.getcompletion "Acp mode plan model " "cmdline")))
(check ":Acp doesn't offer settings already given"
       (vim.deep_equal ["model"] (vim.fn.getcompletion "Acp mode plan " "cmdline"))
       (vim.fn.getcompletion "Acp mode plan " "cmdline"))
(check ":AcpConfig completes only one pair"
       (vim.deep_equal [] (vim.fn.getcompletion "AcpConfig mode plan " "cmdline")))

;; Choosing the agent ---------------------------------------------------------------

(local acp (require :modules.acp))
(local agents (require :modules.acp.agents))
(local transport (require :modules.acp.transport))

(fn notified [f]
  ;; The vim.notify messages f produces.
  (let [messages []
        original vim.notify]
    (set vim.notify (fn [msg] (table.insert messages msg)))
    (let [(ok err) (pcall f)]
      (set vim.notify original)
      (when (not ok) (error err)))
    messages))

(fn has-message [messages text]
  (accumulate [found false _ m (ipairs messages)]
    (or found (not= nil (string.find m text 1 true)))))

;; Argument parsing
(check "a leading sandbox switch is neither an agent nor a setting"
       (and (vim.deep_equal {:sandbox true :settings {}} (acp.parse-args ["sandbox"]))
            (vim.deep_equal {:sandbox false :settings {}} (acp.parse-args ["nosandbox"]))
            (vim.deep_equal {:sandbox true :agent "opencode" :settings {:model "x"}}
                            (acp.parse-args ["sandbox" "opencode" "model" "x"]))
            (= nil (. (acp.parse-args ["model" "x"]) :sandbox))))

(check "no arguments: no agent, no settings"
       (vim.deep_equal {:settings {}} (acp.parse-args [])))
(check "settings only are pairs, as before"
       (vim.deep_equal {:settings {:model "sonnet" :mode "plan"}}
                       (acp.parse-args ["model" "sonnet" "mode" "plan"])))
(check "a leading agent claims the extra argument"
       (vim.deep_equal {:agent "opencode" :settings {:model "x" :mode "y"}}
                       (acp.parse-args ["opencode" "model" "x" "mode" "y"])))
(check "an agent alone is accepted"
       (vim.deep_equal {:agent "opencode" :settings {}} (acp.parse-args ["opencode"])))
(let [(parsed message) (acp.parse-args ["claude" "sonnet"])]
  (check "an agent followed by an unpaired value is refused, not read as a setting"
         (and (= nil parsed)
              (= "acp: settings come in pairs after the agent, e.g. :Acp claude model sonnet"
                 message))
         message))
(let [(parsed message) (acp.parse-args ["opencod" "model" "x"])]
  (check "an odd count with an unknown first argument lists the known agents"
         (and (= nil parsed)
              (= "acp: unknown agent 'opencod' (known: claude, opencode), or settings come in pairs" message))
         message))
(let [(parsed message) (acp.parse-args ["model"])]
  (check "a lone setting name is refused with the same message"
         (and (= nil parsed) (vim.startswith message "acp: unknown agent 'model'"))
         message))
(check "user agents are merged over the built-in ones"
       (do
         (set vim.g.acp-agents {:opencode ["oc" "serve"] :mine "my-agent --acp"})
         (let [ok (and (vim.deep_equal ["claude" "mine" "opencode"] (agents.names))
                       (vim.deep_equal ["oc" "serve"] (. (agents.get :opencode) :cmd))
                       (vim.deep_equal ["my-agent" "--acp"] (. (agents.get :mine) :cmd)))]
           (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})
           ok)))
(check "vim.g.acp-agent-cmd overrides the default agent only"
       (and (= "python3" (. (agents.get :claude) :cmd 1))
            (vim.deep_equal ["python3" (.. here "/fake_agent.py") "opencode"] (. (agents.get :opencode) :cmd))))
(check "vim.g.acp-config picks the default agent"
       (do
         (set vim.g.acp-config {:agent "opencode"})
         (let [ok (and (= "opencode" (agents.default-name))
                       ;; vim.g.acp-agent-cmd now overrides opencode, not claude
                       (= "python3" (. (agents.get :opencode) :cmd 1))
                       (= nil (. (agents.get :opencode) :cmd 3))
                       (= "claude-agent-acp" (. (agents.get :claude) :cmd 1)))]
           (set vim.g.acp-config nil)
           ok)))

;; Environment: every agent drops the API key unless its profile opts out
(set vim.env.ANTHROPIC_API_KEY "secret")
(check "clean-env drops what the profile lists"
       (and (= nil (. (transport.clean-env ["ANTHROPIC_API_KEY"]) :ANTHROPIC_API_KEY))
            (= "secret" (. (transport.clean-env []) :ANTHROPIC_API_KEY))))
(check "claude removes ANTHROPIC_API_KEY, the built-in opencode opts out"
       (and (vim.deep_equal ["ANTHROPIC_API_KEY"] (. (agents.get :claude) :env-remove))
            (vim.deep_equal [] (. (agents.get :opencode) :env-remove))))
(set vim.g.acp-agents {:list ["a" "b"]
                       :str "c d"
                       :prof {:cmd ["e" "f"] :env-remove []}
                       :profstr {:cmd "g h" :env-remove ["X"]}
                       :opencode {:cmd ["oc"]}
                       :claude {:env-remove []}})
(let [got (collect [_ n (ipairs (agents.names))]
            (let [a (agents.get n)] (values n [a.cmd a.env-remove])))]
  (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})
  (check "agent entries may be argv lists, strings or profile tables"
         (vim.deep_equal {:list [["a" "b"] ["ANTHROPIC_API_KEY"]]
                          :str [["c" "d"] ["ANTHROPIC_API_KEY"]]
                          :prof [["e" "f"] []]
                          :profstr [["g" "h"] ["X"]]
                          ;; a built-in keeps what the entry doesn't give
                          :opencode [["oc"] []]
                          :claude [["python3" (.. here "/fake_agent.py")] []]}
                         got)
         got))
(check "vim.g.acp-agent-cmd on a custom default agent still drops the key"
       (do
         (set vim.g.acp-agents {:mine ["claude-agent-acp"]})
         (set vim.g.acp-config {:agent "mine"})
         (let [a (agents.get :mine)
               ok (and (= "python3" (. a.cmd 1)) (vim.deep_equal ["ANTHROPIC_API_KEY"] a.env-remove))]
           (set vim.g.acp-config nil)
           (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})
           ok)))

;; Sandbox: no route out except the proxy ------------------------------------------

(local sandbox (require :modules.acp.sandbox))

(fn argv-index [argv flag a b]
  ;; Position of FLAG A B in ARGV, or nil. Later mounts win, so position matters.
  (var found nil)
  (each [i v (ipairs argv)]
    (when (and (not found)
               (= v flag)
               (= (. argv (+ i 1)) a)
               (or (= b nil) (= (. argv (+ i 2)) b)))
      (set found i)))
  found)

(check "a :sandbox spec is off, deny-all, no network, or a host list"
       (and (= nil (sandbox.normalize nil))
            (= nil (sandbox.normalize false))
            (vim.deep_equal {:net :proxy :allow [] :read [] :write [] :mask nil}
                            (sandbox.normalize true))
            (vim.deep_equal {:net false :read [] :write [] :mask nil}
                            (sandbox.normalize {:net false}))
            (vim.deep_equal {:net :proxy :allow ["a:443"] :read [] :write [] :mask nil}
                            (sandbox.normalize {:allow ["a:443"]}))
            (vim.deep_equal {:net :proxy :allow [] :read ["~/.config/gh"] :write [] :mask nil}
                            (sandbox.normalize {:read ["~/.config/gh"]}))))

(check "a profile's :sandbox reaches agents.get"
       (do
         (set vim.g.acp-agents {:s {:cmd ["x"] :sandbox {:allow ["api.anthropic.com:443"]}}})
         (let [a (agents.get :s)]
           (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})
           (vim.deep_equal {:allow ["api.anthropic.com:443"]} a.sandbox))))

(let [(box problem) (sandbox.prepare {:net false} "")]
  (check "a sandbox with no project directory is refused"
         (and (= nil box) (not= nil problem))))

(let [(box problem) (sandbox.prepare {:net false} ".")
      cwd (vim.fs.normalize (vim.fn.getcwd))]
  (check "a relative project is resolved, never bound as ."
         (and box (not problem)
              (accumulate [seen false i v (ipairs box.prefix)]
                (or seen (and (= v "--bind-try")
                              (= (. box.prefix (+ i 1)) cwd)
                              (= (. box.prefix (+ i 2)) cwd)))))
         (or problem box.prefix)))

(let [project (vim.fn.tempname)
      _ (vim.fn.mkdir project "p")
      (box problem) (sandbox.prepare {:net false} project)]
  (check "a no-network sandbox starts no proxy"
         (and box (not problem) (= nil box.proc) (= nil box.env.HTTPS_PROXY)
              (vim.tbl_contains box.prefix "--unshare-net")
              (= "--" (. box.prefix (length box.prefix))))
         (or problem box.prefix))
  (when box
    (check "the sandbox binds the host read-only with the project, /tmp and the data home writable"
           (let [argv box.prefix
                 data (sandbox.data-dir)]
             (and
               ;; No whole-host writable bind any more.
               (accumulate [ok true i v (ipairs argv)]
                 (and ok (not (and (= v "--dev-bind") (= "/" (. argv (+ i 1)))))))
               (accumulate [seen false i v (ipairs argv)]
                 (or seen (and (= v "--bind-try")
                               (= (. argv (+ i 1)) project)
                               (= (. argv (+ i 2)) project))))
               (accumulate [seen false i v (ipairs argv)]
                 (or seen (and (= v "--bind-try")
                               (= (. argv (+ i 1)) data)
                               (= (. argv (+ i 2)) data))))
               (accumulate [seen false i v (ipairs argv)]
                 (or seen (and (= v "--bind")
                               (= (. argv (+ i 1)) "/tmp")
                               (= (. argv (+ i 2)) "/tmp"))))))
           box.prefix)
    (let [res (vim.system (vim.list_extend (vim.deepcopy box.prefix)
                                           ["/bin/sh" :-c
                                            (.. "touch " (vim.fn.shellescape (.. project "/probe"))
                                                " /tmp/acp-sandbox-probe"
                                                " " (vim.fn.shellescape (.. (sandbox.data-dir) "/acp-sandbox-probe"))
                                                " 2>/dev/null"
                                                "; if [ -e \"$HOME/.ssh\" ] || [ -e \"$HOME/.aws\" ]; then"
                                                " echo home-secrets-visible; else echo home-secrets-absent; fi"
                                                "; if (echo probe > \"$HOME/.acp-probe\") 2>/dev/null; then"
                                                " echo home-writable; else echo home-locked; fi")])
                          {:text true})
          out (res:wait)]
      (check "the agent gets the project, /tmp and its data home, and an empty $HOME"
             (and (vim.uv.fs_stat (.. project "/probe"))
                  (vim.uv.fs_stat "/tmp/acp-sandbox-probe")
                  (vim.uv.fs_stat (.. (sandbox.data-dir) "/acp-sandbox-probe"))
                  ;; ~/.ssh and ~/.aws are absent inside, not read-only.
                  (string.match (tostring out.stdout) "home%-secrets%-absent")
                  ;; $HOME itself is a private tmpfs, so a write lands there and
                  ;; never on the host.
                  (string.match (tostring out.stdout) "home%-writable")
                  (not (vim.uv.fs_stat (.. vim.env.HOME "/.acp-probe"))))
             out)
      (vim.fn.delete (.. project "/probe"))
      (vim.fn.delete "/tmp/acp-sandbox-probe")
      (vim.fn.delete (.. (sandbox.data-dir) "/acp-sandbox-probe"))
      (vim.fn.delete project)))
  (sandbox.stop box))

;; The allowlist is scoped to $HOME, so build a fake one with a secret in it and check
;; the argv rather than what the real home happens to hold.
(when (sandbox.available?)
  (let [fake (vim.fn.tempname)
        real vim.env.HOME
        real-data vim.env.XDG_DATA_HOME]
    (vim.fn.mkdir (.. fake "/.ssh") "p")
    (vim.fn.mkdir (.. fake "/.config/git") "p")
    (vim.fn.writefile ["[user]"] (.. fake "/.gitconfig"))
    (vim.fn.writefile ["PRIVATE KEY"] (.. fake "/.ssh/id_ed25519"))
    (set vim.env.HOME fake)
    (set vim.env.XDG_DATA_HOME nil)
    (let [(box problem) (sandbox.prepare {:net false :read ["~/.config/gh"]}
                                         (vim.fn.tempname))
          argv (or (?. box :prefix) [])
          binds (fn [flag src dst]
                  (accumulate [seen false i v (ipairs argv)]
                    (or seen (and (= v flag)
                                  (= (. argv (+ i 1)) src)
                                  (or (= dst nil) (= (. argv (+ i 2)) dst))))))]
      (check "the sandbox empties $HOME and binds back only the allowlist"
             (and box (not problem)
                  (binds "--tmpfs" fake nil)
                  (binds "--ro-bind" (.. fake "/.gitconfig") (.. fake "/.gitconfig"))
                  (binds "--ro-bind" (.. fake "/.config/git") (.. fake "/.config/git"))
                  ;; A secret on the host never reaches the sandbox...
                  (not (binds "--ro-bind" (.. fake "/.ssh") (.. fake "/.ssh")))
                  (not (binds "--bind-try" (.. fake "/.ssh") (.. fake "/.ssh")))
                  ;; ...and no whole-host or whole-home bind would bring it back.
                  (not (binds "--ro-bind" "/" fake))
                  (not (binds "--dev-bind" fake nil)))
             argv)
      (sandbox.stop box))
    (vim.fn.delete fake :rf)
    (set vim.env.HOME real)
    (set vim.env.XDG_DATA_HOME real-data)))

(check "a sandbox refuses a project that would put $HOME back"
       (let [(box problem) (sandbox.prepare {:net false} vim.env.HOME)]
         (and (= nil box)
              (string.match (tostring problem) "undo the sandbox"))))

(let [dir (vim.fn.tempname)
      file (.. (vim.fn.tempname) ".txt")]
  (vim.fn.mkdir dir "p")
  (vim.fn.writefile ["x"] file)
  (let [(box problem) (sandbox.prepare {:net false :mask [dir file]} (vim.fn.tempname))
        argv (or (?. box :prefix) [])]
    (check "a :mask directory is hidden with a tmpfs and a file with /dev/null"
           (and box (not problem)
                (accumulate [seen false i v (ipairs argv)]
                  (or seen (and (= v "--tmpfs") (= (. argv (+ i 1)) dir))))
                (accumulate [seen false i v (ipairs argv)]
                  (or seen (and (= v "--ro-bind")
                                (= (. argv (+ i 1)) "/dev/null")
                                (= (. argv (+ i 2)) file)))))
           argv)
    (sandbox.stop box))
  (vim.fn.delete dir :rf)
  (vim.fn.delete file))

;; A hook is the one thing in the writable project that runs on the host later.
(let [project (vim.fn.tempname)]
  (vim.fn.mkdir (.. project "/.git/hooks") "p")
  (vim.fn.writefile ["#!/bin/sh" "echo host"] (.. project "/.git/hooks/pre-commit"))
  (let [(box problem) (sandbox.prepare {:net false} project)
        argv (or (?. box :prefix) [])
        hooks (.. project "/.git/hooks")
        project-at (argv-index argv "--bind-try" project project)
        hooks-at (argv-index argv "--ro-bind" hooks hooks)]
    (check "the project is writable but .git/hooks stays read-only, mounted after it"
           (and box (not problem) project-at hooks-at (> hooks-at project-at))
           argv)
    (sandbox.stop box))
  (vim.fn.delete project :rf))

(let [project (vim.fn.tempname)]
  (vim.fn.mkdir project "p")
  (let [(box problem) (sandbox.prepare {:net false} project)
        argv (or (?. box :prefix) [])
        hooks (.. project "/.git/hooks")
        found (accumulate [seen false i v (ipairs argv)]
                (or seen (and (= v "--ro-bind") (= (. argv (+ i 1)) hooks))))]
    (check "a project with no hooks directory gets no hooks mount"
           (and box (not problem) (not found))
           argv)
    (sandbox.stop box))
  (vim.fn.delete project :rf))

;; Repo config and .gitattributes name commands git runs too, so they are immutable.
(let [project (vim.fn.tempname)]
  (vim.fn.mkdir (.. project "/.git") "p")
  (vim.fn.writefile ["[core]"] (.. project "/.git/config"))
  (vim.fn.writefile ["* text=auto"] (.. project "/.gitattributes"))
  (let [(box problem) (sandbox.prepare {:net false} project)
        argv (or (?. box :prefix) [])
        config (.. project "/.git/config")
        attributes (.. project "/.gitattributes")
        project-at (argv-index argv "--bind-try" project project)
        config-at (argv-index argv "--ro-bind" config config)
        attributes-at (argv-index argv "--ro-bind" attributes attributes)]
    (check "repo config and .gitattributes stay read-only, mounted after the project"
           (and box (not problem)
                project-at config-at attributes-at
                (> config-at project-at)
                (> attributes-at project-at))
           argv)
    (sandbox.stop box))
  (vim.fn.delete project :rf))

(let [project (vim.fn.tempname)]
  (vim.fn.mkdir (.. project "/.git/modules/dep/hooks") "p")
  (let [(box problem) (sandbox.prepare {:net false} project)
        argv (or (?. box :prefix) [])
        hooks (.. project "/.git/modules/dep/hooks")
        at (argv-index argv "--ro-bind" hooks hooks)]
    (check "a submodule's hooks under .git/modules stay read-only too"
           (and box (not problem) at)
           argv)
    (sandbox.stop box))
  (vim.fn.delete project :rf))

(let [project (vim.fn.tempname)]
  (vim.fn.mkdir project "p")
  (vim.fn.writefile ["gitdir: /elsewhere"] (.. project "/.git"))
  (let [(box problem) (sandbox.prepare {:net false} project)
        argv (or (?. box :prefix) [])
        dotgit (.. project "/.git")
        at (argv-index argv "--ro-bind" dotgit dotgit)]
    (check "a worktree's .git pointer file is frozen, not writable"
           (and box (not problem) at)
           argv)
    (sandbox.stop box))
  (vim.fn.delete project :rf))

(when (sandbox.available?)
  ;; A local echo server stands in for the model's API, so the test needs no network.
  (let [server (vim.uv.new_tcp)]
    (server:bind "127.0.0.1" 0)
    (server:listen 8
                   (fn []
                     (let [client (vim.uv.new_tcp)]
                       (server:accept client)
                       (client:read_start (fn [_ chunk]
                                            (when chunk (client:write chunk)))))))
    (let [port (. (server:getsockname) :port)
          script (.. vim.g.acp-log-dir "/egress_client.py")
          body (.. "import os, socket, threading\n"
                   "proxy = os.environ.get('HTTPS_PROXY', '')\n"
                   "print('proxy', proxy)\n"
                   "print('all_proxy', os.environ.get('ALL_PROXY', 'unset'))\n"
                   "print('no_proxy', os.environ.get('NO_PROXY', ''))\n"
                   "srv = socket.socket()\n"
                   "srv.bind(('127.0.0.1', 0))\n"
                   "srv.listen(1)\n"
                   "def local():\n"
                   "    c, _ = srv.accept()\n"
                   "    c.sendall(b'local')\n"
                   "    c.close()\n"
                   "threading.Thread(target=local, daemon=True).start()\n"
                   "c = socket.create_connection(('127.0.0.1', srv.getsockname()[1]), 3)\n"
                   "print('loopback', c.recv(16).decode())\n"
                   "c.close()\n"
                   "def connect(hostport):\n"
                   "    host, port = proxy.split('://')[1].split(':')\n"
                   "    c = socket.create_connection((host, int(port)), 5)\n"
                   "    c.sendall(f'CONNECT {hostport} HTTP/1.1\\r\\n\\r\\n'.encode())\n"
                   "    head = b''\n"
                   "    while b'\\r\\n\\r\\n' not in head:\n"
                   "        chunk = c.recv(4096)\n"
                   "        if not chunk: break\n"
                   "        head += chunk\n"
                   "    return c, head.split(b'\\r\\n', 1)[0].decode()\n"
                   "c, line = connect('127.0.0.1:" (tostring port) "')\n"
                   "print('allowed', line)\n"
                   "c.sendall(b'ping\\n')\n"
                   "print('echo', c.recv(64).decode().strip())\n"
                   "c.close()\n"
                   "c, line = connect('blocked.invalid:443')\n"
                   "print('blocked', line)\n"
                   "c.close()\n"
                   "ph, pp = proxy.split('://')[1].split(':')\n"
                   "c = socket.create_connection((ph, int(pp)), 5)\n"
                   "c.sendall(b'GET http://127.0.0.1:" (tostring port) "/x HTTP/1.1\\r\\nHost: h\\r\\n\\r\\n')\n"
                   "print('http', c.recv(200).decode().split('\\r\\n', 1)[0])\n"
                   "c.close()\n"
                   "try:\n"
                   "    socket.create_connection(('1.1.1.1', 443), 2).close()\n"
                   "    print('direct connected')\n"
                   "except OSError as e:\n"
                   "    print('direct', e.errno)\n")]
      (vim.fn.writefile (vim.split body "\n" {:plain true}) script)
      ;; An inherited proxy would be a way around the sandbox's own.
      (set vim.env.ALL_PROXY "socks5://10.9.9.9:9")
      (let [lines []
            (box problem) (sandbox.prepare {:net :proxy :allow [(.. "127.0.0.1:" port)]}
                                           vim.g.acp-log-dir)
            sock (?. box :sock)
            log (?. box :log)]
        (check "the egress proxy starts on a socket" (and box (not problem)) problem)
        (when box
          (let [done []
                (proc err) (transport.start ["python3" script] vim.g.acp-log-dir
                                            {:on-line (fn [l] (table.insert lines l))
                                             :on-exit (fn [_] (table.insert done true))}
                                            [] box)]
            (wait #(= 1 (length done)) 15000)
            (check "the sandboxed agent gets the proxy environment"
                   (and (has-line lines "proxy http://127.0.0.1:8899")
                        (has-line lines "all_proxy unset")
                        (has-line lines "no_proxy localhost,127.0.0.1,::1"))
                   (and proc lines))
            (check "loopback inside the sandbox is the sandbox's own"
                   (has-line lines "loopback local") lines)
            (check "an allow-listed host is reached through the proxy"
                   (and (has-line lines "allowed HTTP/1.1 200 Connection established")
                        (has-line lines "echo ping"))
                   lines)
            (check "plain HTTP goes through the same allowlist"
                   (has-line lines "http GET /x HTTP/1.1") lines)
            (check "a host not on the list is refused"
                   (has-line lines "blocked HTTP/1.1 403 Forbidden") lines)
            (check "nothing reaches the network except through the proxy"
                   (and (not (has-line lines "direct connected"))
                        (accumulate [found false _ l (ipairs lines)]
                          (or found (string.match l "^direct %d+$"))))
                   lines)
            (let [written (vim.fn.readfile log)]
              (check "the proxy logs what it allowed and what it refused"
                     (and (accumulate [ok false _ l (ipairs written)]
                            (or ok (string.find l (.. "ALLOW 127.0.0.1:" port) 1 true)))
                          (accumulate [ok false _ l (ipairs written)]
                            (or ok (string.find l "DENY blocked.invalid:443" 1 true))))
                     written)))
          (sandbox.stop box)
          (check "stopping the session removes the socket" (= nil (vim.uv.fs_stat sock)) sock)))
      (set vim.env.ALL_PROXY nil)
      (server:close)
      (vim.fn.delete script))))

;; A whole session through the sandbox, agent included.
(when (sandbox.available?)
  (set vim.g.acp-agents {:sandboxed {:cmd ["python3" (.. here "/fake_agent.py") "sandboxed"]
                                     :sandbox {:net :proxy :allow []}}})
  (vim.cmd "Acp sandboxed")
  (let [s (session.current)]
    (wait #(?. s :ready) 15000)
    (let [lines (lines-of s.buf)]
      (check "a sandboxed agent still completes the handshake" (?. s :ready) lines)
      (check "the chat says the session is sandboxed"
             (has-line lines "> acp: sandbox: no host allowed") lines))
    (let [box s.sandbox
          sock (?. box :sock)]
      ;; The proxy's log is the only channel; a denial written to it reaches the chat.
      (vim.fn.writefile ["2026-01-01T00:00:00 DENY evil.example:443"] box.log "a")
      (wait #(has-line (lines-of s.buf) "> acp: egress blocked: evil.example:443") 3000)
      (check "a refused host is said in the chat, once"
             (has-line (lines-of s.buf) "> acp: egress blocked: evil.example:443")
             (lines-of s.buf))
      (session.stop s)
      (check "ending a sandboxed session stops the proxy and removes its socket"
             (and box (= nil box.proc) (= nil (vim.uv.fs_stat sock)))
             sock)))
  (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]}))

;; :Acp sandbox and :Acp nosandbox switch it per invocation.
(when (sandbox.available?)
  (vim.cmd "Acp sandbox opencode")
  (let [s (session.current)]
    (wait #(?. s :ready) 15000)
    (check ":Acp sandbox sandboxes an agent whose profile has no policy"
           (and (?. s :sandbox)
                (= "opencode" s.agent.name)
                (has-line (lines-of s.buf) "> acp: sandbox: no host allowed"))
           (lines-of s.buf))
    (vim.cmd "Acp nosandbox")
    (let [s2 (session.current)]
      (wait #(?. s2 :ready) 15000)
      (check ":Acp nosandbox restarts the session outside the sandbox"
             (and (not= s s2) (= nil s2.sandbox) (?. s2 :ready))
             s2.sandbox)
      (session.stop s2))))

;; Starting, switching and focusing
(let [messages (notified #(vim.cmd "Acp opencod model x"))]
  (check "an unknown agent warns and starts nothing"
         (and (= nil (session.current)) (has-message messages "unknown agent 'opencod'"))
         messages))

(vim.cmd "Acp opencode model sonnet")
(local oc (session.current))
(check ":Acp <agent> starts that agent" (and (= "opencode" oc.agent.name) (= "opencode" (. oc.agent.cmd 3))))
(wait #oc.ready)
(check "the agent is told apart by its process" (= "fake opencode" oc.agent.info.name) oc.agent.info)
(check "settings after the agent are applied" (= "sonnet" (. (session.config-option oc :model) :current)))
(check "other agents keep the API key" (= "key" oc.agent.info.version) oc.agent.info)
(check "the statusline names the agent"
       (not= nil (string.find (statusline-of (vim.fn.bufwinid oc.buf)) "[acp opencode · Sonnet 5.5 · Manual" 1 true))
       (statusline-of (vim.fn.bufwinid oc.buf)))

(local messages-same (notified #(vim.cmd "Acp opencode mode plan")))
(wait #(= "plan" (. (session.config-option oc :mode) :current)))
(check "naming the running agent focuses it and applies settings"
       (and (= oc (session.current)) (vim.api.nvim_buf_is_valid oc.buf)
            (= oc.buf (vim.api.nvim_get_current_buf))
            (not (has-message messages-same "switching"))))

(vim.api.nvim_set_current_win start-win)
(vim.cmd "Acp")
(check "no agent named keeps the running one" (and (= oc (session.current)) (= oc.buf (vim.api.nvim_get_current_buf))))

(local messages-switch (notified #(vim.cmd "Acp claude model sonnet")))
(local cl (session.current))
(check "naming another agent starts a new session"
       (and (not= oc cl) (= "claude" cl.agent.name) (not (vim.api.nvim_buf_is_valid oc.buf))))
(check "switching says so" (has-message messages-switch "acp: switching agent from opencode to claude") messages-switch)
(wait #cl.ready)
(check "the new session gets the settings" (= "sonnet" (. (session.config-option cl :model) :current)))
(check "the claude profile drops the API key" (= "no-key" cl.agent.info.version) cl.agent.info)
(check "switching leaves the new session as the only one"
       (= 1 (length (vim.tbl_filter #(vim.startswith (vim.api.nvim_buf_get_name $1) "acp://")
                                    (vim.api.nvim_list_bufs)))))

;; A custom agent (it may run claude) drops the key too
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]
                       :mine ["python3" (.. here "/fake_agent.py") "mine"]})
(vim.cmd "Acp mine")
(local mine (session.current))
(wait #mine.ready)
(check "a custom agent drops the API key" (and (= "mine" mine.agent.name) (= "no-key" mine.agent.info.version))
       mine.agent.info)
(set vim.env.ANTHROPIC_API_KEY nil)

;; :Acp! with no agent named restarts the running session's agent, not the default
(set vim.g.acp-config {:agent "opencode" :mode "plan"})
(vim.cmd "Acp!")
(local restarted (session.current))
(wait #restarted.ready)
(check ":Acp! restarts the current session's agent"
       (and (not= mine restarted) (= "mine" restarted.agent.name) (= "fake mine" restarted.agent.info.name))
       restarted.agent)
(vim.cmd "AcpStop")
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})

;; vim.g.acp-config's agent is the default for new sessions, and is not a setting
(vim.cmd "Acp!")
(local cd (session.current))
(wait #cd.ready)
(check ":Acp! without a session starts the default agent from vim.g.acp-config" (= "opencode" cd.agent.name))
(check "the agent key is not passed as a setting"
       (and (= nil (. cd.requested :agent)) (= "plan" (. cd.requested :mode))
            (not (has-line (lines-of cd.buf) "> acp: unknown setting agent")))
       cd.requested)
(check "the default agent's setting applies" (= "plan" (. (session.config-option cd :mode) :current)))
(set vim.g.acp-config {:agent "opencod"})
(let [messages (notified #(vim.cmd "Acp!"))]
  (check ":Acp! with a session ignores the default agent"
         (and (not (has-message messages "unknown agent")) (= "opencode" (. (session.current) :agent :name)))
         messages))
(vim.cmd "AcpStop")
(let [messages (notified #(vim.cmd "Acp"))]
  (check "an unknown default agent warns" (has-message messages "unknown agent 'opencod' in vim.g.acp-config") messages)
  (check "and starts nothing" (= nil (session.current))))
(set vim.g.acp-config nil)

;; An agent that is also a setting id is refused
(set vim.g.acp-agents {:mode ["python3" (.. here "/fake_agent.py") "mode"]})
(let [(parsed message) (acp.parse-args ["mode"])]
  (check "an agent named like a setting is refused"
         (and (= nil parsed) (not= nil (string.find message "both an agent and a setting" 1 true)))
         message))
(check "completion doesn't offer it as an agent twice"
       (= 1 (length (vim.tbl_filter #(= $1 "mode") (vim.fn.getcompletion "Acp " "cmdline")))))
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})

;; Completion
(vim.cmd "AcpStop")
(check ":Acp completes settings and agent names"
       (vim.deep_equal ["mode" "model" "claude" "opencode" "sandbox" "nosandbox"]
                       (vim.fn.getcompletion "Acp " "cmdline")))
(check ":Acp completes an agent name's prefix"
       (vim.deep_equal ["opencode"] (vim.fn.getcompletion "Acp ope" "cmdline")))
(check ":Acp completes settings after an agent"
       (vim.deep_equal ["mode" "model"] (vim.fn.getcompletion "Acp opencode " "cmdline")))
(check ":Acp completes values after an agent"
       (vim.deep_equal ["default" "sonnet"] (vim.fn.getcompletion "Acp opencode model " "cmdline")))
(check ":Acp counts pairs from after the agent"
       (vim.deep_equal ["model"] (vim.fn.getcompletion "Acp opencode mode plan " "cmdline")))
(check ":Acp offers no agent after the first argument"
       (vim.deep_equal ["model"] (vim.fn.getcompletion "Acp mode plan " "cmdline")))
(check ":AcpConfig doesn't complete agents"
       (vim.deep_equal ["mode" "model"] (vim.fn.getcompletion "AcpConfig " "cmdline")))

;; Resuming an earlier session ----------------------------------------------------------

(local history (require :modules.acp.history))
(local original-select vim.ui.select)
(var picked nil)

(fn stub-select [choose]
  ;; Replaces vim.ui.select: records what was offered and answers with choose(items).
  (set picked nil)
  (set vim.ui.select
       (fn [items opts on-choice]
         (set picked {: items
                      :prompt opts.prompt
                      :labels (icollect [_ i (ipairs items)] (opts.format_item i))})
         (on-choice (choose items)))))

(fn item-with [id]
  (fn [items]
    (accumulate [found nil _ i (ipairs items)] (if (= i.id id) i found))))

(fn count-lines [lines text]
  (length (vim.tbl_filter #(= $1 text) lines)))

(fn line-starting [lines prefix]
  (accumulate [found nil _ l (ipairs lines)] (or found (when (vim.startswith l prefix) l))))

;; The picker's pure parts
(let [now (os.time)
      stamp (fn [secs] (os.date "!%Y-%m-%dT%H:%M:%SZ" (- now secs)))]
  (check "a minute-old session is recent" (= "just now" (history.age (stamp 20) now)))
  (check "ages count minutes, hours and days"
         (and (= "5m ago" (history.age (stamp 300) now))
              (= "3h ago" (history.age (stamp (* 3 3600)) now))
              (= "2d ago" (history.age (stamp (* 2 86400)) now))))
  (check "older than a week shows the date" (= 10 (length (history.age (stamp (* 30 86400)) now))))
  (check "no timestamp, no age" (= "" (history.age nil now))))
(let [sessions [{:id "abc-1" :updated "2026-01-01T00:00:00Z"}
                {:id "abc-2" :updated "2026-03-01T00:00:00Z"}
                {:id "xyz"}]]
  (check "sessions are newest first, undated last"
         (vim.deep_equal ["abc-2" "abc-1" "xyz"] (icollect [_ x (ipairs (history.sort-recent sessions))] x.id)))
  (check "a session is found by its id" (= "abc-2" (. (history.find sessions "abc-2") :id)))
  (check "or by an unambiguous prefix" (= "xyz" (. (history.find sessions "x") :id)))
  (check "an ambiguous prefix finds nothing" (= nil (history.find sessions "abc"))))
(check "a title's first line is the label"
       (vim.startswith (history.label {:id "i" :title "One\nTwo"} (os.time) false) "One")
       (history.label {:id "i" :title "One\nTwo"} (os.time) false))

;; Another project, for the agent to list sessions of
(local elsewhere (.. (vim.fn.tempname) "/elsewhere"))
(vim.fn.mkdir elsewhere :p)
(set vim.env.FAKE_OTHER_CWD elsewhere)
;; An agent that can't load sessions carries on as a new session
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]
                       :resumable ["python3" (.. here "/fake_agent.py") "resumable"]})
(check "AcpResume completes agent names"
       (vim.deep_equal ["resumable"] (vim.fn.getcompletion "AcpResume res" "cmdline")))

(vim.cmd "AcpResume")
(local plain (session.current))
(wait #plain.ready)
(check "an agent without loadSession starts a new session instead"
       (and plain.ready (= "sess-1" plain.session.id)
            (has-line (lines-of plain.buf) "> acp: fake can't load earlier sessions, starting a new session"))
       (lines-of plain.buf))
(vim.cmd "AcpStop")

;; Choosing from this project's sessions, through the agent started for the purpose
(stub-select (item-with "old-1"))
(vim.cmd "AcpResume resumable")
(local r1 (session.current))
(check "the agent started to pick is the one named" (= "resumable" r1.agent.name))
(wait #r1.ready)
(check "the picker offers this project's sessions only, across pages, newest first"
       (and picked (vim.deep_equal ["old-3" "old-2" "old-1"] (icollect [_ i (ipairs picked.items)] i.id)))
       (and picked picked.labels))
(check "labels show the title's first line and how long ago"
       (and (vim.startswith (. picked.labels 2) "Second chat · ")
            (not (string.find (. picked.labels 2) "second line" 1 true))
            (vim.startswith (. picked.labels 1) "(untitled old-3)"))
       picked.labels)
(check "the project's sessions don't show their directory" (not (string.find (. picked.labels 1) "/" 1 true)) picked.labels)
(check "the chosen session is the one loaded" (and r1.ready (= "old-1" r1.session.id)) r1.session.id)
(let [lines (lines-of r1.buf)]
  (check "your replayed prompts are in the chat, whole" (has-line lines "hello there") lines)
  (check "replayed replies are in the chat" (and (has-line lines "Hi there.") (has-line lines "Second answer.")) lines)
  (check "replayed thinking is quoted" (has-line lines ">> pondering") lines)
  (check "replayed tool calls show as lines" (has-line lines "> tool: Read /tmp/x/a.txt — done") lines)
  (check "the second prompt opens its own turn" (has-line lines "second question") lines)
  (check "a heading for each replayed prompt, and one for the input"
         (= 3 (count-lines lines "## You")) lines)
  (check "replays don't invent stop lines" (not (line-starting lines "> stop:")) lines)
  (check "the chat says it resumed the session"
         (not= nil (line-starting lines "> acp: resumed First chat · protocol v1")) lines)
  (check "the chat ends with the input area"
         (vim.deep_equal ["" "## You" ""] (vim.list_slice lines (- (length lines) 2))) lines))
(check "nothing is left of the replay" (and (= nil r1.replay) (= :idle r1.turn.state)))
(check "the replayed usage shows" (and r1.usage (= 5000 r1.usage.used)))
(let [log (vim.fn.readfile r1.log.path)]
  (check "a session with no log of its own gets its replayed turns written to a new one"
         (and (has-line log "resumed: true") (has-line log "session: old-1")
              (has-line log "hello there") (has-line log "Second answer.")
              (= 2 (length (vim.tbl_filter #(vim.startswith $1 "## You") log))))
         log))

;; A resumed session takes prompts, as itself
(vim.cmd "AcpSend plain")
(wait #(= r1.turn.state :idle) 3000)
(check "prompts go to the resumed session" (has-line (lines-of r1.buf) "Plain reply.") (lines-of r1.buf))
(let [log (vim.fn.readfile r1.log.path)]
  (check "and are logged after the replayed turns"
         (and (has-line log "Plain reply.")
              (= 3 (length (vim.tbl_filter #(vim.startswith $1 "## You") log))))
         log))

;; A session that already has a log carries on in it
(local old2-log (.. vim.g.acp-log-dir "/2026-10-02-0900-proj-second-chat.md"))
(vim.fn.writefile ["---" "date: 2026-10-02T09:00" "session: old-2" "---" ""
                   "## You — 09:00" "hello" "" "## Agent" "" "Hi." ""]
                  old2-log)

;; Through a running session; an id skips the picker
(stub-select #(error "the picker should not open"))
(vim.cmd "AcpResume resumable old-2")
(wait #(not= (session.current) r1))
(local r2 (session.current))
(check "resuming ends the running session" (not (vim.api.nvim_buf_is_valid r1.buf)))
(wait #r2.ready)
(check "an id loads that session directly" (and r2.ready (= "old-2" r2.session.id)) r2.session.id)
(check "a multi-line title is cut to its first line"
       (not= nil (line-starting (lines-of r2.buf) "> acp: resumed Second chat · protocol v1"))
       (lines-of r2.buf))
(let [log (vim.fn.readfile old2-log)]
  (check "it carries on in its existing log" (= old2-log r2.log.path))
  (check "the replay isn't written to it again"
         (= 1 (length (vim.tbl_filter #(vim.startswith $1 "## You") log))) log)
  (check "the log notes the resumption" (= "> acp: resumed" (. log (- (length log) 1))) log))
(vim.cmd "AcpSend plain")
(wait #(= r2.turn.state :idle) 3000)
(let [log (vim.fn.readfile old2-log)]
  (check "new turns are appended to it"
         (and (has-line log "Plain reply.") (= 2 (length (vim.tbl_filter #(vim.startswith $1 "## You") log))))
         log))

;; Choosing nothing, or something that isn't there, leaves the running session alone
(stub-select (fn [] nil))
(let [messages (notified #(do (vim.cmd "AcpResume") (vim.wait 300)))]
  (check "cancelling the picker keeps the running session"
         (and (= r2 (session.current)) (vim.api.nvim_buf_is_valid r2.buf)
              (has-message messages "acp: no session chosen"))
         messages))
(let [messages (notified #(do (vim.cmd "AcpResume resumable nope") (vim.wait 300)))]
  (check "an unknown id says so and keeps the running session"
         (and (= r2 (session.current)) (has-message messages "acp: no session matches nope"))
         messages))

;; ! lists every project's sessions, and a session from another project loads there
(stub-select (item-with "other-1"))
(vim.cmd "AcpResume! resumable")
(wait #(not= (session.current) r2))
(local r3 (session.current))
(check "the picker offers every project's sessions"
       (and picked (= 4 (length picked.items)) (= "other-1" (. picked.items 1 :id)))
       (and picked (icollect [_ i (ipairs picked.items)] i.id)))
(check "and shows where each one lives"
       (and (string.find (. picked.labels 1) elsewhere 1 true) true)
       picked.labels)
(wait #r3.ready)
(check "a session from another project loads for that project"
       (and r3.ready (= "other-1" r3.session.id) (= elsewhere r3.session.cwd)
            (= "elsewhere" r3.session.project)
            (= "acp://chat/elsewhere" (vim.api.nvim_buf_get_name r3.buf)))
       r3.session)
(vim.cmd "AcpStop")
(set vim.env.FAKE_OTHER_CWD nil)
(vim.fn.delete (vim.fn.fnamemodify elsewhere ":h") "rf")

;; Cancelling when the agent was started just to pick
(stub-select (fn [] nil))
(vim.cmd "AcpResume resumable")
(local r4 (session.current))
(wait #r4.ready)
(check "cancelling the picker carries on as a new session"
       (and r4.ready (= "sess-1" r4.session.id)
            (has-line (lines-of r4.buf) "> acp: no session chosen, starting a new session"))
       (lines-of r4.buf))
(vim.cmd "AcpStop")

;; A session that fails to load
(let [failed (session.start (agents.get :resumable) {}
                            {:kind :load :id "gone" :cwd (vim.fn.getcwd) :title "Gone"})]
  (wait #(has-line (lines-of failed.buf) "> acp: session/load failed: session not found"))
  (check "a failing load is reported"
         (has-line (lines-of failed.buf) "> acp: session/load failed: session not found")
         (lines-of failed.buf))
  (check "and the session never takes prompts" (not failed.ready))
  (session.stop failed))

(set vim.ui.select original-select)
(set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]})

;; Session summary --------------------------------------------------------------------

(local summary (require :modules.acp.summary))
(local summary-logs (vim.fn.tempname))
(local summary-elsewhere (vim.fn.tempname))
(vim.fn.mkdir summary-logs :p)
(vim.fn.mkdir summary-elsewhere :p)

(fn write-summary-log [name cwd session date prompt reply]
  (vim.fn.writefile
    ["---"
     (.. "date: " date)
     (.. "project: " (vim.fn.fnamemodify cwd ":t"))
     (.. "cwd: " cwd)
     "agent: opencode acp"
     "agent-name: opencode"
     (.. "session: " session)
     "git: none"
     "---"
     "## You — 10:00"
     prompt
     ""
     "## Agent"
     ""
     "> tool: Read x — done"
     ""
     reply
     ""
     "> stop: end_turn"
     ""]
    (.. summary-logs "/" name ".md")))

(write-summary-log "older" (vim.fn.getcwd) "sum-1" "2026-10-21T10:00"
                   "Fix the session summary" "Here is what changed.")
(write-summary-log "newer" (vim.fn.getcwd) "sum-2" "2026-10-22T10:00"
                   "A newer chat" "Newer reply.")
(write-summary-log "elsewhere" summary-elsewhere "sum-3" "2026-10-23T10:00"
                   "Another project's chat" "Elsewhere.")

(let [found (summary.sessions summary-logs (vim.fn.getcwd) false)]
  (check "the summary gathers this project's logs"
         (and (= 2 (length found))
              (vim.deep_equal ["sum-2" "sum-1"] (icollect [_ s (ipairs found)] s.id)))
         (icollect [_ s (ipairs found)] s.id))
  (check "a session's title is its first prompt" (= "A newer chat" (. found 1 :title)))
  (check "the summary previews the first reply"
         (= "Newer reply." (. found 1 :preview))))
(check "the summary can include every project's sessions"
       (= 3 (length (summary.sessions summary-logs (vim.fn.getcwd) true))))

(let [real-log-dir vim.g.acp-log-dir
      before-tabs (length (vim.fn.gettabinfo))
      before-wins (length (vim.api.nvim_list_wins))]
  (set vim.g.acp-log-dir summary-logs)
  (vim.cmd "AcpSummary")
  (check "AcpSummary opens a split, not a tab" (= before-tabs (length (vim.fn.gettabinfo))))
  (let [buf (vim.api.nvim_get_current_buf)
        chat (lines-of buf)
        path (.. summary-logs "/newer.md")
        path-line (.. "`" (vim.fn.fnamemodify path ":~") "`")]
    (var row nil)
    (each [i l (ipairs chat) &until row]
      (when (= l path-line) (set row i)))
    (check "AcpSummary opens a markdown buffer" (= "markdown" (. vim.bo buf :filetype)))
    (check "the summary lists the project's sessions, newest first"
           (and (has-line chat "## 1. A newer chat")
                (has-line chat "## 2. Fix the session summary"))
           chat)
    (check "each session names its log" (has-line chat path-line) chat)
    (check "the resume link carries the session id"
           (has-line chat "[Resume this session](acp://resume/sum-2)") chat)
    (check "the first reply is previewed" (has-line chat "> Newer reply.") chat)
    (check "the summary has a resume mapping"
           (= "function" (type (?. (vim.fn.maparg "<CR>" "n" false true) :callback))))
    (when row
      (vim.api.nvim_win_set_cursor 0 [row 2])
      (check "gf on a log line finds the log file"
             (= (vim.fn.fnamemodify path ":p")
                (vim.fn.fnamemodify (vim.fn.expand "<cfile>") ":p"))
             (vim.fn.expand "<cfile>")))
    (vim.cmd "AcpSummary!")
    (let [all-chat (lines-of (vim.api.nvim_get_current_buf))]
      (check "AcpSummary! lists every project's sessions"
             (and (has-line all-chat "## 1. Another project's chat")
                  (has-line all-chat "## 2. A newer chat"))
             all-chat))
    (each [_ name (ipairs [(.. "acp://summary/" (vim.fn.fnamemodify (vim.fn.getcwd) ":t"))
                           "acp://summary/all"])]
      (let [b (vim.fn.bufnr name)]
        (when (> b 0)
          (each [_ w (ipairs (vim.fn.win_findbuf b))]
            (vim.api.nvim_win_close w true))
          (vim.api.nvim_buf_delete b {:force true}))))
    (check "the summary splits close cleanly"
           (and (= before-tabs (length (vim.fn.gettabinfo)))
                (= before-wins (length (vim.api.nvim_list_wins))))
           [before-tabs (length (vim.fn.gettabinfo))
            before-wins (length (vim.api.nvim_list_wins))])
    (set vim.g.acp-log-dir real-log-dir)))
(vim.fn.delete summary-logs "rf")
(vim.fn.delete summary-elsewhere "rf")

;; Credits ----------------------------------------------------------------------------

(local credits (require :modules.acp.credits))
(check "usage limits show the fullest Go window and the picked budgets"
       (= "go 43% · $12.50/$50.00"
          (credits.summary
            (vim.json.encode {:location {:directory "/x"}
                              :data {:workspace {:id "w" :usageURL "u"}
                                     :go {:rolling {:percent 10 :limited false :resetsAt 0}
                                          :weekly {:percent 42.6 :limited false :resetsAt 0}
                                          :monthly {:percent 20 :limited false :resetsAt 0}}
                                     :budgets [{:limit 50 :spent 12.5 :picked true}
                                               {:limit 100 :spent 1 :picked false}]}}))))
(check "a limited Go window says so, every budget shows when none is picked"
       (= "go limited · $1.00/$5.00 $2.00/$9.00"
          (credits.summary
            (vim.json.encode {:data {:go {:rolling {:percent 100 :limited true :resetsAt 0}}
                                     :budgets [{:limit 5 :spent 1 :picked false}
                                               {:limit 9 :spent 2 :picked false}]}}))))
(check "opencode stats show the spend over their range"
       (and (= "30d $69.25"
               (credits.summary (vim.json.encode {:range {:from 0 :to (* 29.5 86400000)}
                                                  :sessions 28 :cost 69.2514})))
            (= "1d $1.00"
               (credits.summary (vim.json.encode {:range {:from 0 :to 3600000} :cost 1})))))
(check "not signed in shows nothing" (= nil (credits.summary "{\"location\":{},\"data\":null}")))
(check "plain output shows its first line" (= "£4.20 left" (credits.summary "£4.20 left\nmore\n")))
(check "nothing to show is nil" (= nil (credits.summary "  \n")))
(check "profiles may set or turn off the credits command"
       (do
         (set vim.g.acp-agents {:opencode {:credits-cmd false} :mine {:cmd "m" :credits-cmd "c --x"}})
         (let [ok (and (= nil (. (agents.get :opencode) :credits-cmd))
                       (vim.deep_equal ["c" "--x"] (. (agents.get :mine) :credits-cmd))
                       (= nil (. (agents.get :claude) :credits-cmd)))]
           (set vim.g.acp-agents nil)
           (and ok (= "opencode" (. (agents.get :opencode) :credits-cmd 1))))))

(let [counter (vim.fn.tempname)]
  (set vim.g.acp-credits true)
  (set vim.g.acp-agents
       {:opencode {:cmd ["python3" (.. here "/fake_agent.py") "opencode"]
                   :credits-cmd ["sh" "-c" (.. "n=$(($(cat " counter " 2>/dev/null || echo 0) + 1)); "
                                               "echo $n > " counter "; "
                                               "[ \"$PWD\" = \"$1\" ] && echo \"credits $n\"")
                                 "sh" "{cwd}"]}})
  (vim.cmd "Acp! opencode")
  (local cr (session.current))
  (wait #(and cr.ready cr.credits))
  (check "credits are fetched once the session starts, in its directory" (= "credits 1" cr.credits) cr.credits)
  (vim.cmd "AcpSend plain")
  (wait #(= "credits 2" cr.credits))
  (check "and again after each prompt" (= "credits 2" cr.credits) cr.credits)
  (check "the statusline shows the session cost and the credits"
         (not= nil (string.find (statusline-of (vim.fn.bufwinid cr.buf)) "· 25% · $0.13 · credits 2]" 1 true))
         (statusline-of (vim.fn.bufwinid cr.buf)))
  (set cr.agent.credits-cmd ["false"])
  (vim.cmd "AcpSend plain")
  (wait #(= :idle cr.turn.state))
  (vim.wait 300)
  (check "a failing credits command keeps the last figure" (= "credits 2" cr.credits) cr.credits)
  (vim.cmd "AcpStop")
  (vim.fn.delete counter)
  (set vim.g.acp-credits false)
  (set vim.g.acp-agents {:opencode ["python3" (.. here "/fake_agent.py") "opencode"]}))

;; Agent-supplied rows don't leak markdown syntax into the lines below ----------------

(let [buf (vim.api.nvim_create_buf false true)]
  (vim.api.nvim_buf_set_lines buf 0 -1 false
    ["> tool: printf ' ```diff ' — done"
     ""
     "### Agent"
     ""
     "A normal reply."])
  (render.markdown buf)
  (vim.api.nvim_buf_call buf
    (fn []
      (local group (fn [row] (vim.fn.synIDattr (vim.fn.synID row 1 1) :name)))
      (local in-code?
        (fn [row]
          (accumulate [found false _ id (ipairs (vim.fn.synstack row 1))]
            (or found (= "markdownCode" (vim.fn.synIDattr id :name))))))
      (local protected?
        (fn [row]
          (accumulate [found false _ id (ipairs (vim.fn.synstack row 1))]
            (or found (= "AcpUiLine" (vim.fn.synIDattr id :name))))))
      (check "a tool title with a fence doesn't open a code block"
             (not (in-code? 3))
             (group 3))
      (check "the line after a tool title is still normal"
             (= "" (group 5))
             (group 5))
      (check "the tool row itself is protected"
             (protected? 1)
             (group 1))))
  (vim.api.nvim_buf_delete buf {:force true}))

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
(vim.fn.delete vim.g.acp-egress-log-dir "rf")
(check "the real settings cache is left alone"
       (vim.deep_equal real-cache-before
                       (when (= 1 (vim.fn.filereadable real-cache)) (vim.fn.readfile real-cache))))
(vim.fn.delete vim.g.acp-config-cache)
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
