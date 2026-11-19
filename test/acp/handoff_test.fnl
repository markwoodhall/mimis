;; End-to-end tests for :AcpRun and g!, handing a command's output to the agent, with a fake aws
;; on the path and test/acp/fake_agent.py as the agent.
;; Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/handoff_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(set vim.g.acp-agent-cmd ["python3" (.. here "/fake_agent.py")])
(set vim.g.acp-agents {})
(set vim.g.acp-credits false)
(set vim.g.acp-log-dir (vim.fn.tempname))
(set vim.g.acp-debug-log (vim.fn.tempname))
(set vim.g.acp-config-cache (vim.fn.tempname))
(set vim.g.acp-egress-log-dir (vim.fn.tempname))
(set vim.g.acp-output-dir (vim.fn.tempname))
(set vim.g.acp-screenshot-seconds 0)

(local session (require :modules.acp.session))
(local render (require :modules.acp.render))
(local failures [])

(fn out [line]
  (io.stdout:write (.. line "\n")))

(fn check [name ok detail]
  (if ok
    (out (.. "ok   " name))
    (do
      (table.insert failures name)
      (out (.. "FAIL " name (if (not= detail nil) (.. "\n     " (vim.inspect detail)) ""))))))

(fn wait [pred ms]
  (vim.wait (or ms 3000) pred 10))

(local bin (vim.fn.tempname))
(vim.fn.mkdir bin "p")
(vim.fn.writefile
  ["#!/bin/sh"
   "case \"$*\" in"
   "  *fail*) echo 'token expired' >&2; exit 255 ;;"
   "  *start-query*badquery*) echo q2; exit ;;"
   "  *start-query*) echo q1; exit ;;"
   "  *'--query-id q2 --query status'*) echo Failed; exit ;;"
   "  *'--query status'*) [ -e \"$0.polled\" ] && echo Complete || { touch \"$0.polled\"; echo Running; }; exit ;;"
   "  *get-query-results*) echo \"$*\" > \"$0.results-args\""
   "    echo '{\"status\":\"Complete\",\"statistics\":{\"recordsMatched\":1},\"results\":[[{\"field\":\"@timestamp\",\"value\":\"t\"},{\"field\":\"@message\",\"value\":\"m\"},{\"field\":\"@ptr\",\"value\":\"p\"}]]}'"
   "    exit ;;"
   "esac"
   "echo '{\"args\": \"'\"$*\"'\"}'"
   "echo 'noise' >&2"]
  (.. bin "/aws"))
(vim.fn.setfperm (.. bin "/aws") "rwxr-xr-x")
(set vim.env.PATH (.. bin ":" vim.env.PATH))

(fn files []
  (vim.fn.glob (.. vim.g.acp-output-dir "/aws-*.json") true true))

(fn run [command]
  ;; In a tab of its own, as the terminal takes over the window it runs in.
  (vim.cmd "tabnew")
  (vim.cmd command)
  (let [buf (vim.api.nvim_get_current_buf)]
    (vim.fn.jobwait [(. vim.bo buf :channel)] 5000)
    (vim.wait 100)
    (vim.api.nvim_buf_delete buf {:force true})))

(fn prompt [s]
  (vim.api.nvim_buf_get_lines s.buf (- (render.input-row s) 1) -1 false))

(fn set-prompt [s lines]
  (vim.api.nvim_buf_set_lines s.buf (- (render.input-row s) 1) -1 false lines))

;; With a session ---------------------------------------------------------------------

(vim.cmd "Acp")
(local s (session.current))
(wait #s.ready)

(set-prompt s ["why?"])
(run "AcpRun aws logs filter-log-events --start-time `echo 5`\\%")
(let [saved (. (files) 1)
      lines (prompt s)]
  (check ":AcpRun aws saves stdout, without stderr, as readable JSON"
         (and saved (= "{\"args\": \"logs filter-log-events --start-time 5%\"}"
                       (table.concat (vim.fn.readfile saved) "\n")))
         (when saved (vim.fn.readfile saved)))
  (check ":AcpRun adds the file to the prompt, after what you'd typed, with room to carry on"
         (and saved (= 3 (length lines)) (= "why?" (. lines 1)) (= "" (. lines 3))
              (not= nil (string.find (. lines 2) saved 1 true)))
         lines)
  (check ":AcpRun tells the agent the command as the shell ran it"
         (not= nil (string.find (or (. lines 2) "")
                                "Output of: aws logs filter-log-events --start-time `echo 5`% " 1 true))
         lines)
  (check ":AcpRun sends nothing by itself" (= s.turn.state :idle) s.turn.state)
  (check "the output directory ignores itself in git"
         (vim.deep_equal ["*"] (vim.fn.readfile (.. vim.g.acp-output-dir "/.gitignore"))))
  (when saved (vim.fn.delete saved)))

;; A cursor waiting on the prompt's empty last line stays on an empty line
(set-prompt s [""])
(vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
(render.cursor-to s)
(render.add-to-prompt s "a reference")
(check "a cursor on the empty prompt line stays on the empty line"
       (and (vim.deep_equal ["a reference" ""] (prompt s))
            (= (vim.api.nvim_buf_line_count s.buf)
               (. (vim.api.nvim_win_get_cursor 0) 1)))
       (prompt s))

(set-prompt s [""])
(run "AcpRun aws fail")
(check ":AcpRun with no output leaves no file" (= 0 (length (files))) (files))
(check ":AcpRun with no output leaves the prompt alone" (vim.deep_equal [""] (prompt s)) (prompt s))

(run "Aws logs plain")
(check ":Aws hands nothing over"
       (and (= 0 (length (files))) (vim.deep_equal [""] (prompt s)))
       (files))

;; Logs Insights ----------------------------------------------------------------------

(fn insights-files []
  (vim.fn.glob (.. vim.g.acp-output-dir "/insights-*.json") true true))

(set vim.env.AWS_INSIGHTS_POLL "0")
(run "AcpRun aws --profile p logs start-query --log-group-name g --query-string 'fields @message | limit 5'")
(let [saved (. (insights-files) 1)
      lines (prompt s)]
  (check ":AcpRun aws start-query waits for the query and saves its results as rows"
         (and saved (vim.deep_equal {:statistics {:recordsMatched 1}
                                     :results [{"@timestamp" "t" "@message" "m"}]}
                                    (vim.json.decode (table.concat (vim.fn.readfile saved) "\n"))))
         (when saved (vim.fn.readfile saved)))
  (check ":AcpRun aws start-query polls until the query is complete"
         (= 1 (vim.fn.filereadable (.. bin "/aws.polled"))))
  (check ":AcpRun aws start-query asks for the results with the same profile"
         (vim.startswith (or (?. (vim.fn.readfile (.. bin "/aws.results-args")) 1) "")
                         "--no-cli-pager --profile p logs get-query-results --query-id q1")
         (vim.fn.readfile (.. bin "/aws.results-args")))
  (check ":AcpRun aws start-query adds the file to the prompt"
         (and saved (not= nil (string.find (or (. lines 1) "") saved 1 true))
              (not= nil (string.find (. lines 1) "Output of: aws --profile p logs start-query" 1 true)))
         lines)
  (when saved (vim.fn.delete saved)))

(set-prompt s [""])
(run "AcpRun aws logs start-query --query-string badquery")
(check ":AcpRun aws start-query whose query fails leaves no file" (= 0 (length (insights-files))) (insights-files))
(check ":AcpRun aws start-query whose query fails leaves the prompt alone" (vim.deep_equal [""] (prompt s)) (prompt s))

;; Code cards -------------------------------------------------------------------------
;; g! on a shell card the agent wrote runs it once you've seen it, and its output goes
;; back as a comment on the card, sent straight away.

(fn chat-lines []
  (vim.api.nvim_buf_get_lines s.buf 0 -1 false))

(fn last-row-of [text]
  (accumulate [found nil i l (ipairs (chat-lines))]
    (if (vim.startswith l text) i found)))

(fn card-reply [prompt-text]
  (session.send-prompt s prompt-text)
  (wait #(= s.turn.state :idle)))

(fn press-g! [row]
  ;; Returns the terminal it opened, once its command has finished, or nil.
  (vim.api.nvim_set_current_win (. (vim.fn.win_findbuf s.buf) 1))
  (vim.api.nvim_win_set_cursor 0 [row 0])
  (vim.api.nvim_feedkeys "g!" :x false)
  (let [buf (vim.api.nvim_get_current_buf)]
    (when (not= buf s.buf)
      (vim.fn.jobwait [(. vim.bo buf :channel)] 5000)
      (vim.wait 100)
      buf)))

(fn close [buf]
  (when buf (vim.api.nvim_buf_delete buf {:force true})))

(local real-input vim.ui.input)
(local real-confirm vim.fn.confirm)
(var asked nil)
(fn answer-with [f]
  (set vim.ui.input (fn [opts on-done] (set asked opts.default) (on-done (f opts.default)))))

(set-prompt s [""])
(card-reply "shell card")
(answer-with #$)
(let [term (press-g! (+ (last-row-of "$ aws logs filter-log-events") 1))]
  (check "g! asks first, the card's lines as one command, without the prompt"
         (= asked "aws logs filter-log-events --start-time 5% --x '#y'") asked)
  (wait #(and (= s.turn.state :idle) (last-row-of "Noted.")))
  (let [saved (. (files) 1)
        log (table.concat (vim.fn.readfile s.log.path) "\n")]
    (check "g! runs the command as written, % and # untouched"
           (and saved (= "{\"args\": \"logs filter-log-events --start-time 5% --x #y\"}"
                         (table.concat (vim.fn.readfile saved) "\n")))
           (when saved (vim.fn.readfile saved)))
    (check "g! comments on the card with where the output is, and sends it"
           (and saved (string.find log "Inline comment on this part of" 1 true)
                (string.find log (.. "I ran it, its output is saved to " saved) 1 true))
           log)
    (check "the reply is in a thread under the card"
           (let [card (last-row-of "$ aws logs filter-log-events")
                 reply (last-row-of "Noted.")]
             (and card reply (> reply card)
                  (vim.startswith (or (. (chat-lines) (- reply 1)) "") "## Agent ↳")))
           (chat-lines))
    (check "and the prompt is left alone" (vim.deep_equal [""] (prompt s)) (prompt s))
    (when saved (vim.fn.delete saved)))
  (close term))

(answer-with #(.. $1 " --more"))
(let [term (press-g! (last-row-of "$ aws logs filter-log-events"))]
  (wait #(= s.turn.state :idle))
  (let [saved (. (files) 1)
        log (table.concat (vim.fn.readfile s.log.path) "\n")]
    (check "a command changed before it runs is the one that runs"
           (and saved (string.find (table.concat (vim.fn.readfile saved)) "--more" 1 true))
           (when saved (vim.fn.readfile saved)))
    (check "and the comment says how it was run"
           (string.find log "I ran it as `aws logs filter-log-events --start-time 5% --x '#y' --more`" 1 true)
           log)
    (when saved (vim.fn.delete saved)))
  (close term))

(answer-with #nil)
(let [term (press-g! (last-row-of "$ aws logs filter-log-events"))]
  (check "g! cancelled runs nothing" (and (= nil term) (= 0 (length (files)))) (files)))

(card-reply "script card")
(var confirmed nil)
(set vim.fn.confirm (fn [message] (set confirmed message) 1))
(let [term (press-g! (+ (last-row-of "cat <<EOF") 1))]
  (check "a card of several lines is shown whole to confirm"
         (= confirmed "Run this?\n\ncat <<EOF\n{\"n\": 1}\nEOF") confirmed)
  (wait #(= s.turn.state :idle))
  (let [saved (. (vim.fn.glob (.. vim.g.acp-output-dir "/cat-*.txt") true true) 1)]
    (check "and runs as a script, a heredoc and all"
           (and saved (vim.deep_equal ["{\"n\": 1}"] (vim.fn.readfile saved)))
           (when saved (vim.fn.readfile saved)))
    (when saved (vim.fn.delete saved)))
  (close term))
(set vim.fn.confirm real-confirm)

(card-reply "python card")
(set asked nil)
(let [term (press-g! (last-row-of "print(1)"))]
  (check "g! on a card that isn't shell runs nothing" (and (= nil term) (= nil asked)) asked))
(set vim.ui.input real-input)
(set-prompt s [""])

;; Screenshots ------------------------------------------------------------------------

(fn fake-tool [name lines]
  (vim.fn.writefile (vim.list_extend ["#!/bin/sh"
                                      "[ -n \"$FAKE_SHOT_FAIL\" ] && { echo 'it failed' >&2; exit 1; }"]
                                     lines)
                    (.. bin "/" name))
  (vim.fn.setfperm (.. bin "/" name) "rwxr-xr-x"))

(fake-tool "import" ["printf region > \"$1\""])
(fake-tool "xclip" ["printf '%s' \"$*\""])

(fn shots []
  (vim.fn.glob (.. vim.g.acp-output-dir "/screenshot-*.png") true true))

(fn shot [command]
  ;; Returns once the prompt has its line, or after a moment if none is coming.
  (let [before (length (prompt s))]
    (vim.cmd command)
    (wait #(not= before (length (prompt s))) 1000)
    (vim.wait 100)))

(shot "AcpScreenshot")
(let [saved (. (shots) 1)
      lines (prompt s)]
  (check ":AcpScreenshot saves what you selected"
         (and saved (vim.deep_equal ["region"] (vim.fn.readfile saved)))
         (shots))
  (check ":AcpScreenshot adds the file to the prompt"
         (and saved (= 2 (length lines)) (= "" (. lines 2))
              (vim.startswith (. lines 1) "Screenshot saved to ")
              (not= nil (string.find (. lines 1) saved 1 true)))
         lines)
  (check ":AcpScreenshot sends nothing by itself" (= s.turn.state :idle) s.turn.state)
  (when saved (vim.fn.delete saved)))

(set-prompt s [""])
(shot "AcpScreenshot clipboard")
(let [saved (. (shots) 1)]
  (check ":AcpScreenshot clipboard asks for the copied image as a PNG"
         (and saved (vim.deep_equal ["-selection clipboard -t image/png -o"] (vim.fn.readfile saved)))
         (when saved (vim.fn.readfile saved)))
  (when saved (vim.fn.delete saved)))

(set-prompt s [""])
(vim.cmd "AcpScreenshot 1")
(vim.wait 300)
(check ":AcpScreenshot N doesn't start selecting straight away" (= 0 (length (shots))) (shots))
(wait #(= 2 (length (prompt s))) 3000)
(let [saved (. (shots) 1)]
  (check ":AcpScreenshot N selects once the wait is over"
         (and saved (vim.deep_equal ["region"] (vim.fn.readfile saved)))
         (shots))
  (when saved (vim.fn.delete saved)))

(set-prompt s [""])
(set vim.g.acp-screenshot-seconds nil)
(vim.cmd "AcpScreenshot")
(vim.wait 300)
(check ":AcpScreenshot waits by default, to get to another workspace"
       (= 0 (length (shots))) (shots))
(set vim.g.acp-screenshot-seconds 0)
;; The default wait, 10 seconds, has begun already.
(wait #(= 2 (length (prompt s))) 13000)
(check ":AcpScreenshot selects after the default wait" (= 1 (length (shots))) (shots))
(each [_ saved (ipairs (shots))]
  (vim.fn.delete saved))

(set-prompt s [""])
(set vim.g.acp-screenshot-seconds 30)
(shot "AcpScreenshot 0")
(check ":AcpScreenshot 0 selects straight away" (= 1 (length (shots))) (shots))
(each [_ saved (ipairs (shots))]
  (vim.fn.delete saved))
(shot "AcpScreenshot clipboard")
(check ":AcpScreenshot clipboard doesn't wait" (= 1 (length (shots))) (shots))
(set vim.g.acp-screenshot-seconds 0)
(each [_ saved (ipairs (shots))]
  (vim.fn.delete saved))

;; With 'cmdheight' 0 a message is a hit-enter prompt, which holds up Neovim's timers.
(set-prompt s [""])
(let [real-notify vim.notify
      said []]
  (set vim.notify (fn [message] (table.insert said message)))
  (vim.cmd "AcpScreenshot 1")
  (vim.uv.sleep 1500)
  (check ":AcpScreenshot N selects even if Neovim is held up meanwhile"
         (= 1 (length (shots))) (shots))
  (wait #(= 2 (length (prompt s))) 3000)
  (set vim.notify real-notify)
  (check ":AcpScreenshot says nothing, so there's no prompt to dismiss"
         (= 0 (length said)) said))
(each [_ saved (ipairs (shots))]
  (vim.fn.delete saved))

(set-prompt s [""])
(set vim.env.FAKE_SHOT_FAIL "1")
(shot "AcpScreenshot")
(shot "AcpScreenshot clipboard")
(set vim.env.FAKE_SHOT_FAIL nil)
(check "a cancelled screenshot leaves no file" (= 0 (length (shots))) (shots))
(check "a cancelled screenshot leaves the prompt alone" (vim.deep_equal [""] (prompt s)) (prompt s))

(shot "AcpScreenshot nonsense")
(check "an unknown source takes nothing"
       (and (= 0 (length (shots))) (vim.deep_equal [""] (prompt s)))
       (shots))

(session.stop s)

;; With no session --------------------------------------------------------------------

(run "AcpRun aws logs waiting")
(check "with no session no agent is started" (= nil (session.current)))
(let [saved (. (files) 1)]
  (vim.cmd "Acp")
  (let [s (session.current)
        lines (prompt s)]
    (check "the next session's prompt has the waiting output"
           (and saved (= 2 (length lines)) (not= nil (string.find (. lines 1) saved 1 true)))
           lines)
    (check "the cursor is ready under it"
           (= (vim.api.nvim_buf_line_count s.buf)
              (. (vim.api.nvim_win_get_cursor (vim.fn.bufwinid s.buf)) 1)))
    (session.stop s)))
(vim.cmd "Acp")
(let [s (session.current)]
  (check "the session after that starts with an empty prompt"
         (vim.deep_equal [""] (prompt s))
         (prompt s))
  (session.stop s))

(vim.fn.delete vim.g.acp-log-dir "rf")
(vim.fn.delete vim.g.acp-debug-log)
(vim.fn.delete vim.g.acp-config-cache)
(vim.fn.delete vim.g.acp-egress-log-dir "rf")
(vim.fn.delete vim.g.acp-output-dir "rf")
(vim.fn.delete bin "rf")
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
