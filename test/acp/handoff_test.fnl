;; End-to-end tests for :Aws!, handing a command's output to the agent, with a fake aws
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
(run "Aws! logs filter-log-events --start-time `echo 5`\\%")
(let [saved (. (files) 1)
      lines (prompt s)]
  (check ":Aws! saves stdout, without stderr, as readable JSON"
         (and saved (= "{\"args\": \"--no-cli-pager logs filter-log-events --start-time 5%\"}"
                       (table.concat (vim.fn.readfile saved) "\n")))
         (when saved (vim.fn.readfile saved)))
  (check ":Aws! adds the file to the prompt, after what you'd typed, with room to carry on"
         (and saved (= 3 (length lines)) (= "why?" (. lines 1)) (= "" (. lines 3))
              (not= nil (string.find (. lines 2) saved 1 true)))
         lines)
  (check ":Aws! tells the agent the command as the shell ran it"
         (not= nil (string.find (or (. lines 2) "")
                                "Output of: aws logs filter-log-events --start-time `echo 5`% " 1 true))
         lines)
  (check ":Aws! sends nothing by itself" (= s.turn.state :idle) s.turn.state)
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
(run "Aws! fail")
(check ":Aws! with no output leaves no file" (= 0 (length (files))) (files))
(check ":Aws! with no output leaves the prompt alone" (vim.deep_equal [""] (prompt s)) (prompt s))

(run "Aws logs plain")
(check ":Aws without the bang hands nothing over"
       (and (= 0 (length (files))) (vim.deep_equal [""] (prompt s)))
       (files))

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
(wait #(= 2 (length (prompt s))) 5000)
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

(run "Aws! logs waiting")
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
