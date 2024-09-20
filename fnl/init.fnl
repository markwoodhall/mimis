;; Default options
(local _ (require :modules.options))
(local package (require :packages.package))

(package.enable 
  {;; Keymaps
   :modules.whichkey []
   :modules.keymaps []

   ;; Structure and syntax
   :modules.paredit [:fennel :clojure] 
   :modules.treesitter [:fennel :clojure :lua :gitcommit :sql :org]
   :modules.surround []

   ;; Language support
   :modules.fennel []
   :modules.clojure []
   :modules.sql []
   :modules.org []
   ;;:modules.janet []

   ;; Command line wrappers
   :modules.cmdline.npm []
   :modules.cmdline.aws []
   :modules.cmdline.docker []
   :modules.cmdline.common []

   ;; Editor integrations
   :modules.lsp [:fennel :clojure :sql]
   :modules.git []
   :modules.telescope []
   :modules.statusline []
   :modules.quickfix []
   :modules.colors []})

(package.setup
  {;; Keymaps
   :modules.whichkey []
   :modules.keymaps []

   ;; Language Support
   :modules.fennel []
   :modules.clojure []
   :modules.sql []
   :modules.org {:org-babel-like true}
   ;;:modules.janet []

   ;; Command line wrappers
   :modules.cmdline.npm [] 
   :modules.cmdline.aws [] 
   :modules.cmdline.docker [] 
   :modules.cmdline.common []

   ;; Editor integration
   :modules.lsp 
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
   :modules.git []
   :modules.colors 
   {:theme :catppuccin
    :colorscheme :catppuccin-mocha
    :background :dark
    :post-setup (fn []
                  (vim.api.nvim_set_hl 0 "WinSeparator" {:fg "#1e1e2e" :bg "#1e1e2e"}))}
   :modules.telescope [:lsp :projects :finder :git :buffers] 
   :modules.statusline {:lsp true :theme :catppuccin} 
   :modules.quickfix [] 

   ;; Structure and syntax
   :modules.paredit []
   :modules.treesitter [:fennel :clojure :lua :gitcommit :sql]
   :modules.surround []
   })
