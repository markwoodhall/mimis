(local plugins (require :plugins))

(var treesitter-languages [])
(var treesitter-parsers [])
(var treesitter-loaded nil)

(local enable-hooks
  {:modules.packages.fennel [:fennel]
   :modules.packages.clojure [:clojure]
   :modules.packages.sql [:sql]
   :modules.fennel [:fennel]
   :modules.clojure [:clojure]
   :modules.sql [:sql]
   :modules.git [:gitcommit]
   :modules.org [:org]})

(fn enable [languages module-hook]
  (let [mimis (require :mimis) 
        languages (or languages 
                      (. enable-hooks module-hook) 
                      [])]
    (set treesitter-languages (mimis.concat treesitter-languages languages))
    (plugins.register {:nvim-treesitter/nvim-treesitter {:do ":TSUpdate" :for treesitter-languages}})))

(local setup-hooks
  {:modules.packages.fennel [:fennel]
   :modules.packages.clojure [:clojure]
   :modules.packages.sql [:sql]
   :modules.clojure [:clojure]
   :modules.fennel [:fennel]
   :modules.git [:gitcommit]
   :modules.sql [:sql]
   :modules.org [:org]})

(fn setup [parsers module-hook]
  (let [mimis (require :mimis)
        parsers (or parsers 
                    (. setup-hooks module-hook) 
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
