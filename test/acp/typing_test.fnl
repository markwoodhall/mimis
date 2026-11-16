;; Agent output while you type in the chat, against the render module alone: no agent,
;; so it runs in a moment. Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/typing_test.fnl')"
;; Exits non-zero if anything fails.

(local render (require :modules.acp.render))
(local failures [])

(fn out [line]
  (io.stdout:write (.. line "\n")))

(fn check [name ok detail]
  (if ok
    (out (.. "ok   " name))
    (do
      (table.insert failures name)
      (out (.. "FAIL " name (if detail (.. "\n     " (vim.inspect detail)) ""))))))

(fn lines-of [buf]
  (vim.api.nvim_buf_get_lines buf 0 -1 false))

(fn has-line [lines text]
  (accumulate [found false _ l (ipairs lines)]
    (or found (= l text))))

(local s {:session {:project "typing" :cwd "/tmp"}})
(render.create-buffers s)
(render.show s "")
(vim.cmd "only")

(fn prompt []
  (vim.api.nvim_buf_get_lines s.buf (- (render.input-row s) 1) -1 false))

(fn transcript []
  (vim.api.nvim_buf_get_lines s.buf 0 (- (render.input-row s) 3) false))

;; Insert-mode mappings run agent writes mid-typing; <F9> notes what the chat holds then.
(var agent #nil)
(var seen nil)
(vim.keymap.set :i "<F8>" #(agent) {:buffer s.buf})
(vim.keymap.set :i "<F9>" #(set seen {:transcript (transcript) :prompt (prompt)
                                       :mode (. (vim.api.nvim_get_mode) :mode)})
                {:buffer s.buf})

(fn type-keys [keys]
  (vim.api.nvim_feedkeys (vim.keycode keys) :x false))

(fn settle []
  ;; InsertLeave flushes on the next tick.
  (vim.wait 50 #false))

;; Output outside insert mode goes straight in
(render.status s "before typing")
(check "output when you aren't typing lands at once"
       (has-line (transcript) "> acp: before typing") (lines-of s.buf))

;; Output while typing waits
(local block {:type :line :line "> permission: Run it — awaiting choice"})
(set agent (fn []
             (render.append-text s "\n\nstreamed while you typed")
             (render.add-line s block)
             (render.attach-lines s block ["" "  1. Yes" "  2. No"])
             (set block.line "> permission: Run it — Yes")
             (render.detach-lines s block)
             (render.update-line s block)))
(vim.api.nvim_win_set_cursor 0 [(render.input-row s) 0])
(type-keys "ihello<F8> world<F9><Esc>")
(check "nothing is written to the chat while you type"
       (and seen (vim.startswith seen.mode "i")
            (not (has-line seen.transcript "streamed while you typed")))
       seen)
(check "your typing is untouched meanwhile"
       (and seen (vim.deep_equal ["hello world"] seen.prompt)) seen)
(settle)
(let [t (transcript)]
  (check "leaving insert mode writes what waited, in order"
         (and (has-line t "streamed while you typed")
              (has-line t "> permission: Run it — Yes")
              (not (has-line t "  1. Yes")))
         (lines-of s.buf)))
(check "the prompt stays below it all, as typed"
       (and (vim.deep_equal ["hello world"] (prompt))
            (= "## You" (. (lines-of s.buf) (- (render.input-row s) 1))))
       (lines-of s.buf))

;; A pause in typing, with no completion menu, lets output through
;; (Each feedkeys leaves insert mode at its end, so one sequence does it all.)
(var paused-seen nil)
(vim.keymap.set :i "<F7>" (fn []
                            (render.status s "while paused")
                            (vim.api.nvim_exec_autocmds :CursorHoldI {:buffer s.buf})
                            (set paused-seen (transcript))
                            (set agent #(render.status s "typing again")))
                {:buffer s.buf})
(type-keys "A again<F7>x<F8><F9><Esc>")
(check "a pause in typing writes what waited"
       (and paused-seen (has-line paused-seen "> acp: while paused")) paused-seen)
(check "typing again holds output again"
       (and seen (not (has-line seen.transcript "> acp: typing again"))) seen)
(settle)
(check "and it lands once you stop"
       (and (has-line (transcript) "> acp: typing again")
            (vim.deep_equal ["hello world againx"] (prompt)))
       (lines-of s.buf))

;; Typing in another buffer doesn't hold the chat
(vim.cmd "new")
(vim.keymap.set :i "<F8>" #(render.status s "from elsewhere") {:buffer 0})
(type-keys "ix<F8><Esc>")
(check "typing in another buffer doesn't hold the chat"
       (has-line (transcript) "> acp: from elsewhere"))
(vim.cmd "bwipe!")

(render.wipe s)
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
