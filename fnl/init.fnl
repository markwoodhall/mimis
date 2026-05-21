;; Default options
(local _ (require :modules.options))
(local package (require :packages.package))

(vim.cmd "packadd cfilter")

(package.enable 
  {;; Keymaps
   :modules.keymaps []

   ;; Structure and syntax
   :modules.surround []

   ;; Language support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.packages.sql []
   :modules.terraform []

   :modules.org []

   ;; Command line wrappers
   :modules.cmdline.npm []
   :modules.cmdline.aws []
   :modules.cmdline.docker []
   :modules.cmdline.common []
   :modules.cmdline.chatgpt []

   ;; Editor integrations
   :modules.git []
   :modules.statusline []
   :modules.quickfix []
   :modules.colors []}
  :latest)

(set vim.g.mimis-notes-path "/home/markwoodhall/notes")
(set vim.g.mimis-notes-pandoc-opts "--template default.html -c https://cdn.simplecss.org/simple.min.css")

;;(let [ui2 (require "vim._core.ui2")]
;;  (ui2.enable))

(package.setup
  {;; Keymaps
   :modules.keymaps []

   ;; Language Support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.packages.sql []
   :modules.terraform []

   :modules.org [:org-babel-like :notes]

   ;; Command line wrappers
   :modules.cmdline.npm [] 
   :modules.cmdline.aws [] 
   :modules.cmdline.docker [] 
   :modules.cmdline.common []
   :modules.cmdline.chatgpt []

   ;; Editor integration
   :modules.git []
   :modules.colors 
   {:theme :catppuccin
    :colorscheme :catppuccin-mocha
    :background :dark
    :post-setup (fn [])}
   :modules.statusline []
   :modules.quickfix [] 

   ;; Structure and syntax
   :modules.surround []})
