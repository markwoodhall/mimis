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
   :modules.indentline [] 
   :modules.colors []}
  :stable)

(set vim.g.mimis-notes-path "/home/markwoodhall/Insync/mark.woodhall@gmail.com/GoogleDrive/notes/markwoodhall")
(set vim.g.mimis-notes-pandoc-opts "--template default.html -c https://cdn.simplecss.org/simple.min.css")

(package.setup
  {;; Keymaps
   :modules.whichkey []
   :modules.keymaps []

   ;; Language Support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.packages.sql []
   :modules.org [:org-babel-like :notes]
   ;;:modules.janet []

   ;; Command line wrappers
   :modules.cmdline.npm [] 
   :modules.cmdline.aws [] 
   :modules.cmdline.docker [] 
   :modules.cmdline.common []

   ;; Editor integration
   :modules.git [:fugitive]
   :modules.colors 
   {:theme :catppuccin
    :colorscheme :catppuccin
    :background :dark
    :post-setup (fn [])}
   :modules.telescope [:lsp :projects :finder :git :buffers]
   :modules.statusline [:lsp :catppuccin]
   :modules.quickfix [] 
   :modules.indentline [] 

   ;; Structure and syntax
   :modules.surround []})
