;; Run by acp_test.fnl in a separate Neovim, which it then kills with SIGKILL.
;; Finishes one turn, starts a second that stalls on a permission prompt, then
;; writes the log path to $ACP_TEST_MARKER and waits to be killed.

(set vim.g.acp-agent-cmd ["python3" (.. (vim.fn.stdpath :config) "/test/acp/fake_agent.py")])
(set vim.g.acp-log-dir vim.env.ACP_TEST_LOG_DIR)
(set vim.g.acp-debug-log vim.env.ACP_TEST_DEBUG_LOG)
(local session (require :modules.acp.session))
(vim.cmd "Acp")
(local s (session.current))
(vim.wait 5000 #s.ready 10)
(session.send-prompt s "completed turn")
(vim.wait 5000 #(not= nil s.permission) 10)
(vim.cmd "AcpAllow")
(vim.wait 5000 #(and (= s.turn.state :idle) s.log.path) 10)

(session.send-prompt s "slow")
(vim.wait 5000 #(not= nil s.permission) 10)
(vim.fn.writefile [s.log.path] vim.env.ACP_TEST_MARKER)
(vim.wait 60000 #false 100)
