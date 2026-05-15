(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
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
