(local plugins (require :plugins))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (mimis.try-add-treesitter-path :gitcommit "0.0.36-1")
  (plugins.register 
    {:tpope/vim-fugitive :always
     :lewis6991/gitsigns.nvim :always }))

(fn setup []
  (let [gs (require :gitsigns)] 
    (gs.setup)))

{: enable
 : setup
 : depends }
