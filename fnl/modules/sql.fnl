(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (plugins.register
    {:tpope/vim-dadbod {:on [:DBUI :DBUIFindBuffer]} 
     :kristijanhusak/vim-dadbod-ui {:on [:DBUI :DBUIFindBuffer]} 
     :kristijanhusak/vim-dadbod-completion {:for :sql}})
  (set vim.g.db_ui_save_location "~/dotfiles")
  (set vim.g.db_ui_execute_on_save 0))

(fn setup [])

{: enable
 : setup 
 : depends }
