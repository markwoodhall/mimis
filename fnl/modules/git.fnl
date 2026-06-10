(local plugins (require :plugins))

(fn depends [])

(fn enable []
  (plugins.register 
    {:tpope/vim-fugitive :always
     :lewis6991/gitsigns.nvim :always }))

(fn setup []
  (let [gs (require :gitsigns)] 
    (gs.setup)))

{: enable
 : setup
 : depends }
