;; Shading of your prompts and the agent's replies in the chat, against the render
;; module alone: no agent, so it runs in a moment. Run from anywhere:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/shade_test.fnl')"
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

(local s {:session {:project "shade" :cwd "/tmp"}})
(render.create-buffers s)
(render.show s "")
(vim.cmd "only")

(render.status s "starting")
(render.begin-turn s {:prompt "first line\n\nsecond paragraph" :time "09:00"})
(render.append-text s "A reply.\n\nMore of it.")
(local tool {:type :line :line "> tool: Read x — done"})
(render.add-line s tool)
(render.attach-lines s tool ["" "#### Input" "details"])
(render.append-text s ">> thinking\n\nAfter the tool.")

(fn shaded []
  ;; Each line of the chat with its shade, as "group|line".
  (let [lines (vim.api.nvim_buf_get_lines s.buf 0 -1 false)
        shades (render.shades s 0 (- (length lines) 1))]
    (icollect [i l (ipairs lines)]
      (.. (or (. shades (- i 1)) "-") "|" l))))

(local got (shaded))
(fn has [entry] (vim.tbl_contains got entry))

(check "notes before any turn are plain" (has "-|> acp: starting") got)
(check "your prompt is shaded as yours, heading and blank lines too"
       (and (has "AcpYou|## You — 09:00") (has "AcpYou|first line") (has "AcpYou|")
            (has "AcpYou|second paragraph"))
       got)
(check "the agent's reply is shaded as its own, blank lines inside it too"
       (and (has "AcpAgent|## Agent") (has "AcpAgent|A reply.") (has "AcpAgent|More of it.")
            (has "AcpAgent|After the tool."))
       got)
(check "tool lines and their expansions are plain"
       (and (has "-|> tool: Read x — done") (has "-|#### Input") (has "-|details")) got)
(check "thinking is plain" (has "-|>> thinking") got)
(check "the input area is shaded as yours"
       (= "AcpYou|## You" (. got (- (render.input-row s) 1))) got)

(render.detach-lines s tool)
(check "collapsed details leave no shade behind"
       (not (vim.tbl_contains (shaded) "-|details")) (shaded))

(check "the groups have backgrounds of their own"
       (do
         (require :modules.acp)
         ((. (require :modules.acp) :setup))
         (let [you (vim.api.nvim_get_hl 0 {:name :AcpYou :link false})
               agent (vim.api.nvim_get_hl 0 {:name :AcpAgent :link false})]
           (and you.bg agent.bg (not= you.bg agent.bg))))
       [(vim.api.nvim_get_hl 0 {:name :AcpYou}) (vim.api.nvim_get_hl 0 {:name :AcpAgent})])

;; What reaches the screen: headless Neovim draws nothing, so a second one is started
;; with this one as its UI, and its cells are read back.
(let [child-setup (.. "lua local r = require('modules.acp.render') "
                      "require('modules.acp').setup() "
                      "local s = {session = {project = 'screen', cwd = '/tmp'}} "
                      "r['create-buffers'](s) vim.cmd('enew') r.show(s, '') vim.cmd('only') "
                      "r['begin-turn'](s, {prompt = 'mine', time = '09:00'}) "
                      "r['append-text'](s, 'theirs') "
                      "vim.g.acp_screen_ready = true")
      chan (vim.fn.jobstart ["nvim" "--embed" "-c" child-setup] {:rpc true})
      request (fn [...] (vim.rpcrequest chan ...))]
  (request :nvim_ui_attach 60 12 {:rgb true})
  (vim.wait 5000 #(= true (request :nvim_get_var :acp_screen_ready)) 50)
  (request :nvim_command "redraw!")
  (let [background (fn [row col] (?. (request :nvim__inspect_cell 1 row col) 2 :background))
        group-bg (fn [name] (. (request :nvim_get_hl 0 {: name}) :bg))
        rows (request :nvim_exec_lua "return vim.api.nvim_buf_get_lines(0, 0, -1, false)" [])]
    (check "the shades reach the screen, across the whole width"
           (and (= (group-bg :AcpYou) (background 1 0) (background 1 40))
                (= (group-bg :AcpAgent) (background 4 0) (background 4 40)))
           rows))
  (vim.fn.jobstop chan))

(render.wipe s)
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
