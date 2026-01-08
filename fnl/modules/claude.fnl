(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn enable []
  (plugins.register
    {:folke/snacks.nvim :always
     :coder/claudecode.nvim :always}))

(fn setup []
  (let [cc (require :claudecode)
        wk (require :which-key)]
    (cc.setup)
    (mimis.leader-map "n" "cs" "<cmd>ClaudeCode<cr>" {:desc "claude-code-start"})
    (mimis.leader-map "n" "co" "<cmd>ClaudeCodeOpen<cr>" {:desc "claude-code-open"})
    (mimis.leader-map "n" "cc" "<cmd>ClaudeCodeClose<cr>" {:desc "claude-code-close"})
    (mimis.leader-map "n" "cf" "<cmd>ClaudeCodeFocus<cr>" {:desc "claude-code-focus"})
    (mimis.leader-map "n" "cda" "<cmd>ClaudeCodeDiffAccept<cr>" {:desc "diff-accept"})
    (mimis.leader-map "n" "cdd" "<cmd>ClaudeCodeDiffDeny<cr>" {:desc "diff-deny"})
    (wk.add
      [{1 (.. nvim.g.mapleader "c") :group "claude-code"}
       {1 (.. nvim.g.mapleader "cd") :group "claude-code-diff"}])))

{: enable
 : setup}
