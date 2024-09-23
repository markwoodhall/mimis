;; Default options
(local _ (require :modules.options))
(local package (require :packages.package))

(package.enable 
  {;; Keymaps
   :modules.whichkey []
   :modules.keymaps []

   ;; Structure and syntax
   :modules.surround []

   ;; Language support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.packages.sql []
   :modules.org []
   ;;:modules.janet []

   ;; Command line wrappers
   :modules.cmdline.npm []
   :modules.cmdline.aws []
   :modules.cmdline.docker []
   :modules.cmdline.common []

   ;; Editor integrations
   :modules.git []
   :modules.telescope []
   :modules.statusline []
   :modules.quickfix []
   :modules.colors []}
  :stable)

(package.setup
  {;; Keymaps
   :modules.whichkey []
   :modules.keymaps []

   ;; Language Support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.packages.sql []
   :modules.org {:org-babel-like true}
   ;;:modules.janet []

   ;; Command line wrappers
   :modules.cmdline.npm [] 
   :modules.cmdline.aws [] 
   :modules.cmdline.docker [] 
   :modules.cmdline.common []

   ;; Editor integration
   :modules.git []
   :modules.colors 
   {:theme :catppuccin
    :colorscheme :catppuccin
    :background :dark
    :post-setup (fn []
                  (vim.api.nvim_set_hl 0 "WinSeparator" {:fg "#1e1e2e" :bg "#1e1e2e"}))}
   :modules.telescope [:lsp :projects :finder :git :buffers] 
   :modules.statusline {:lsp true :mimis-repl true :theme :duskfox} 
   :modules.quickfix [] 

   ;; Structure and syntax
   :modules.surround []
   })
