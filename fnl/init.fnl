;; Default options
(local _ (require :modules.options))

;; Supporting
(local projects (require :modules.projects))

;; Package
(local package (require :packages.package))

;; Lsp
(local lsp (require :modules.lsp))

;; Version control
(local git (require :modules.git))

;; Plugins
(local plugins (require :plugins))

(plugins.begin)

;; Keymaps
(package.enable
  {:modules.whichkey []
   :modules.keymaps []})

;; Supporting
(projects.enable)

;; Structure and syntax
(package.enable 
  {:modules.paredit [:fennel :clojure] 
   :modules.treesitter [:fennel :clojure :lua :gitcommit :sql]
   :modules.surround []})

;; Language support
(package.enable
  {:modules.fennel []
   :modules.clojure []
   :modules.sql []})

;; Lsp
(lsp.enable [:fennel :clojure :sql])

;; Source control
(git.enable)

;; Cmdline wrappers
(package.enable 
  {:modules.cmdline.npm []
   :modules.cmdline.aws []
   :modules.cmdline.common []})

;; Editor
(package.enable 
  {:modules.git []
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

  ;; Supporting
  (projects.setup ["project.clj" "shadow-cljs.edn" "pom.xml" "*.sln"])

  ;; Language support
  (package.setup 
    {:modules.fennel []
     :modules.clojure []
     :modules.sql []})

  ;; Lsp setup
  (lsp.setup 
    ;; Add additional language servers here. Internally uses lspconfig, see
    ;; available servers here https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    [:clojure_lsp :fennel_ls]
    ;; Configure filetype completion sources here
    {:fennel
     [{:name "nvim_lsp" :keyword_length 2}
      {:name "buffer" :keyword_length 2}]
     :clojure
     [{:name "nvim_lsp"}
      {:name "buffer"}]
     :sql
     [{:name "vim-dadbod-completion"}
      {:name "buffer"}]})

  ;; Cmdline wrappers
  (package.setup 
    {:modules.cmdline.npm [] 
     :modules.cmdline.aws [] 
     :modules.cmdline.common []})

  ;; Editor
  (package.setup 
    {:modules.git []
     :modules.colors []
     :modules.telescope [:lsp :projects :finder :git] 
     :modules.statusline [] 
     :modules.quickfix []})

  ;; Structure and syntax
  (package.setup 
    {:modules.paredit []
     :modules.treesitter []
     :modules.surround []}))
