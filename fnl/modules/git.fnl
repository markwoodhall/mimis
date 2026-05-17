(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-gitcommit/0.0.36-1"))
  (plugins.register 
    {:tpope/vim-fugitive {:on [:G :Git :Gvdiffsplit]}
     :lewis6991/gitsigns.nvim :always }))

(fn setup []
  (mimis.leader-map 
    "n" 
    "gg" 
    ":silent vimgrep `git ls-files $(git rev-parse --show-toplevel)`<left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><space>" {:desc "find-in-git"})
  (mimis.leader-map "n" "gd" ":Gvdiffsplit<CR>" {:desc "git-diff"})
  (mimis.leader-map "n" "gs" ":G<CR>" {:desc "git-status"})

  (let [wk (require :which-key)
        gs (require :gitsigns)] 
    (gs.setup)
    (wk.add 
      [{1 (.. nvim.g.mapleader "g") :group "git"}])))

{: enable
 : setup
 : depends }
