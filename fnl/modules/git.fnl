(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.1/tree-sitter-gitcommit/0.0.36-1"))
  (plugins.register 
    {:tpope/vim-fugitive {:on [:G :Git :Gvdiffsplit]}
     :lewis6991/gitsigns.nvim :always }))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))]

    (when (. o :fugitive)
      (mimis.leader-map "n" "gd" ":Gvdiffsplit<CR>" {:desc "git-diff"})
      (mimis.leader-map "n" "gs" ":G<CR>" {:desc "git-status"}))

    (let [wk (require :which-key)
          gs (require :gitsigns)] 
      (gs.setup)
      (wk.add 
        [{1 (.. nvim.g.mapleader "g") :group "git"}]))))

{: enable
 : setup
 : depends }
