(local plugins (require :plugins))
(local mimis (require :mimis))

(fn enable []
  (plugins.register
    {:coder/claudecode.nvim :always}))

(fn setup []
  (let [cc (require :claudecode)]
    (cc.setup)
    (mimis.leader-map "n" "cs" "<cmd>ClaudeCode<cr>" {:desc "claude-code-start"})
    (mimis.leader-map "n" "cf" "<cmd>ClaudeCodeFocus<cr>" {:desc "claude-code-focus"})
    (mimis.leader-map "n" "cda" "<cmd>ClaudeCodeDiffAccept<cr>" {:desc "diff-accept"})
    (mimis.leader-map "n" "cdd" "<cmd>ClaudeCodeDiffDeny<cr>" {:desc "diff-deny"})))

{: enable
 : setup }
