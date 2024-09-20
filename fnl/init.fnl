;; Default options
(local _ (require :modules.options))
(local package (require :packages.package))
(local plugins (require :plugins))

(plugins.begin)

;; Keymaps
(package.enable
  {:modules.whichkey []
   :modules.keymaps []})

;; Structure and syntax
(package.enable 
  {:modules.paredit [:fennel :clojure :janet] 
   :modules.treesitter [:fennel :clojure :janet :lua :gitcommit :sql]
   :modules.surround []})

;; Language support
(package.enable
  {:modules.fennel []
   :modules.clojure []
   :modules.sql []})

;; Cmdline wrappers
(package.enable 
  {:modules.cmdline.npm []
   :modules.cmdline.aws []
   :modules.cmdline.common []})

;; Editor
(package.enable 
  {:modules.lsp [:fennel :clojure :sql]
   :modules.projects []
   :modules.git []
   :modules.telescope []
   :modules.statusline []
   :modules.quickfix []
   :modules.colors []})

(plugins.end)

;; Setup modules
(do
  ;; Keymaps
  (package.setup
    {:modules.whichkey []
     :modules.keymaps []})

  ;; Language support
  (package.setup 
    {:modules.fennel []
     :modules.clojure []
     :modules.janet []
     :modules.sql []})

  ;; Cmdline wrappers
  (package.setup 
    {:modules.cmdline.npm [] 
     :modules.cmdline.aws [] 
     :modules.cmdline.common []})

  ;; Editor
  (package.setup 
    {:modules.lsp 
     {:servers [:clojure_lsp :fennel_ls :sqlls]
      :completion-sources 
      {:fennel
       [{:name "nvim_lsp" :keyword_length 2}
        {:name "buffer" :keyword_length 2}]
       :clojure
       [{:name "nvim_lsp"}
        {:name "buffer"}]
       :sql
       [{:name "vim-dadbod-completion"}
        {:name "buffer"}]}}
     :modules.projects {:patterns ["project.clj" "shadow-cljs.edn" "pom.xml" "*.sln"]}
     :modules.git []
     :modules.colors {:theme :catppuccin}
     :modules.telescope [:lsp :projects :finder :git :buffers] 
     :modules.statusline {:lsp true :theme :catppuccin} 
     :modules.quickfix []})

  ;; Structure and syntax
  (package.setup 
    {:modules.paredit []
     :modules.treesitter [:fennel :clojure :janet_simple :lua :gitcommit :sql]
     :modules.surround []}))
