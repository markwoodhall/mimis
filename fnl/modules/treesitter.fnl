(local plugins (require :plugins))
(local ft (require :modules.filetypes))

(var treesitter-languages [])
(var treesitter-parsers [])
(var treesitter-loaded nil)

(fn enable [languages module-hook]
  (let [mimis (require :mimis) 
        languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set treesitter-languages (mimis.concat treesitter-languages languages))
    (plugins.register {:nvim-treesitter/nvim-treesitter {:do ":TSUpdate" :for treesitter-languages}})))

(local module-parsers ft.module-filetypes)

(fn setup [parsers module-hook]
  (let [mimis (require :mimis)
        parsers (or parsers 
                    (. module-parsers module-hook) 
                    [])]
    (set treesitter-parsers (mimis.concat treesitter-parsers parsers))
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
                 {:ensure_installed treesitter-parsers
                  :sync_install false
                  :ignore_install ["org"]
                  :auto_install true
                  :highlight 
                  {:enable true :additional_vim_regex_highlighting []}}))
             (set treesitter-loaded true))))})))

{: enable 
 : setup }
