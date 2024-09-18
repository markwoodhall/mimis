;; Default options
(local _ (require :modules.options))

;; Colors
(local colors (require :modules.colors))

;; Keymaps 
(local whichkey (require :modules.whichkey))
(local keymaps (require :modules.keymaps))

;; Supporting
(local projects (require :modules.projects))
(local paredit (require :modules.paredit))
(local treesitter (require :modules.treesitter))
(local surround (require :modules.surround))

;; Languages
(local fennel (require :modules.fennel))
(local clojure (require :modules.clojure))
(local sql (require :modules.sql))

;; Aesthetic
(local statusline (require :modules.statusline))
(local quickfix (require :modules.quickfix))

;; Lsp
(local lsp (require :modules.lsp))

;; Version control
(local git (require :modules.git))

;; Cmdline wrappers
(local npm (require :modules.cmdline.npm))


(vim.call "plug#begin")
;; Enable modules
(do 
  ;; Keymaps
  (whichkey.enable)
  (keymaps.enable)

  ;; Supporting
  (projects.enable)
  (paredit.enable [:fennel :clojure])
  (treesitter.enable [:fennel :clojure :lua :gitcommit :sql])
  (surround.enable)

  ;; Languages
  (fennel.enable)
  (clojure.enable)
  (sql.enable)

  ;; Lsp
  (lsp.enable [:fennel :clojure :sql])

  ;; Source control
  (git.enable)

  ;; Cmdline wrappers
  (npm.enable)

  ;; Aesthetic
  (quickfix.enable)
  (statusline.enable)
  (colors.enable))

(vim.call "plug#end")	

;; Setup modules
(do
  ;; Colors
  (colors.setup)

  ;; Keymaps
  (whichkey.setup)
  (keymaps.setup)

  ;; Supporting
  (paredit.setup)
  (projects.setup ["project.clj" "shadow-cljs.edn" "pom.xml" "*.sln"])
  (surround.setup)

  ;; Languages 
  (fennel.setup)
  (clojure.setup)
  (sql.setup)

  ;; Lsp setup
  (lsp.setup 
    ;; Add additional language servers here. Internally uses lspconfig, see
    ;; avialable servers here https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
    [:clojure_lsp :sqlls :fennel_ls]
    ;; Configure filetype completion sources here
    {:fennel
     [{:name "nvim_lsp" :keyword_length 2}
      {:name "buffer" :keyword_length 2}]
     :clojure
     [{:name "nvim_lsp" :keyword_length 2}
      {:name "buffer" :keyword_length 2}]
     :sql
     [{:name "vim-dadbod-completion"}
      {:name "buffer"}]})

  ;; Source control
  (git.setup)

  ;; Cmdline wrappers
  (npm.setup)

  ;; Aesthetic
  (quickfix.setup)
  (statusline.setup)

  ;; treesitter
  (treesitter.setup))