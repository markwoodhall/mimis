(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (plugins.register 
    {:nvim-lua/plenary.nvim :always
     :lewis6991/gitsigns.nvim :always
     :neogitorg/neogit :always }))

(fn setup []
  (let [ng (require :neogit)]
    (ng.setup {})
    (mimis.leader-map "n" "gs" (fn [] (ng.open {:kind :split_below_all})) {:desc "git-status"}))
  (let [wk (require :which-key)
        gs (require :gitsigns)] 
    (gs.setup)
    (wk.add 
      [{1 (.. nvim.g.mapleader "g") :group "git"}])))

{: enable
 : setup
 : depends }
