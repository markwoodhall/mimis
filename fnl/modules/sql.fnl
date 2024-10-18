(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter
   :modules.lsp])

(fn enable []
  (plugins.register
    {:tpope/vim-dadbod {:on [:DBUI :DBUIFindBuffer]} 
     :kristijanhusak/vim-dadbod-ui {:on [:DBUI :DBUIFindBuffer]}
     :kristijanhusak/vim-dadbod-completion {:for :sql}}))

(fn setup []
  (set vim.g.db_ui_save_location "~/dotfiles")
  (let [group (vim.api.nvim_create_augroup "mimis-sql-lsp-dadbod" {:clear true})]
    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern :sql
       :group group
       :desc "Setup lsp completion sources for specific filetypes"
       :callback 
       (partial 
         vim.schedule 
         (fn []
           (let [cmp (require :cmp)]
             (cmp.setup.filetype 
               :sql
               {:sources [{:name :nvim_lsp}
                           {:name :vim-dadbod-completion}]}))))})))

{: enable
 : setup 
 : depends }
