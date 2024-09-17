(local Plug (. vim.fn "plug#"))

(fn enable []
  (Plug "tpope/vim-dadbod" {:on :DBUI})
  (Plug "kristijanhusak/vim-dadbod-ui" {:on :DBUI})
  (Plug "kristijanhusak/vim-dadbod-completion" {:for :sql})
  (set vim.g.db_ui_save_location "~/dotfiles"))

(fn setup [])

{: enable
 : setup }
