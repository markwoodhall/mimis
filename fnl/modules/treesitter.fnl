(local plugins (require :plugins))

(var treesitter-languages [])
(var treesitter-loaded nil)

(fn enable [languages]
  (plugins.register {"nvim-treesitter/nvim-treesitter" {:do ":TSUpdate" :for languages}})
  (set treesitter-languages languages))

(fn setup [parsers]
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
               {:ensure_installed parsers
                :sync_install false
                :ignore_install ["org"]
                :auto_install true
                :highlight 
                {:enable true :additional_vim_regex_highlighting []}}))
           (set treesitter-loaded true))))}))

{: enable 
 : setup }
