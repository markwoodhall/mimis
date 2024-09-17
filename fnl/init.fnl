(local _ (require :modules.options))
(local colors (require :modules.colors))
(local whichkey (require :modules.whichkey))
(local keymaps (require :modules.keymaps))
(local projects (require :modules.projects))
(local paredit (require :modules.paredit))
(local treesitter (require :modules.treesitter))
(local fennel (require :modules.fennel))
(local clojure (require :modules.clojure))
(local statusline (require :modules.statusline))
(local quickfix (require :modules.quickfix))
(local lsp (require :modules.lsp))
(local git (require :modules.git))
(local sql (require :modules.sql))

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

  ;; Languages
  (fennel.enable)
  (clojure.enable)
  (sql.enable)

  ;; Lsp
  (lsp.enable [:fennel :clojure :sql])

  ;; Source control
  (git.enable)

  ;; Aesthetic
  (quickfix.enable)
  (statusline.enable)
  (colors.enable))

(vim.call "plug#end")	

;; Setup modules
(do

  (colors.setup)

  (whichkey.setup)
  (keymaps.setup)

  (paredit.setup)
  (projects.setup ["project.clj" "shadow-cljs.edn" "pom.xml" "*.sln"])

  (fennel.setup)
  (clojure.setup)
  (sql.setup)

  (lsp.setup 
    [:clojure_lsp :sqlls :fennel_ls]
    {:fennel
     [{:name "nvim_lsp" :keyword_length 2}
      {:name "buffer" :keyword_length 2}]
     :clojure
     [{:name "nvim_lsp" :keyword_length 2}
      {:name "buffer" :keyword_length 2}]
     :sql
     [{:name "vim-dadbod-completion"}
      {:name "buffer"}]})

  (git.setup)

  (quickfix.setup)
  (statusline.setup)
  (treesitter.setup))
