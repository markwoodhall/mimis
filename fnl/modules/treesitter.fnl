(local plugins (require :plugins))

(var treesitter-languages [])
(var treesitter-loaded nil)

(fn enable [languages]
  (plugins.register {"nvim-treesitter/nvim-treesitter" {:do ":TSUpdate" :for languages}})
  (set treesitter-languages languages))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern treesitter-languages
     :group (vim.api.nvim_create_augroup "mimis-treesitter" {:clear true})
     :desc "Setup treesitter for specific filetypes"
     :callback 
     (partial 
       vim.schedule 
       (fn []
         (when (not treesitter-loaded)
           (let [ts (require "nvim-treesitter.configs")]
             (ts.setup 
               {:ensure_installed treesitter-languages
                :sync_install false
                :auto_install true
                :highlight 
                {:enable true :additional_vim_regex_highlighting []}}))
           (set treesitter-loaded true))))}))

{: enable 
 : setup }
