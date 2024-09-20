(local nvim (require :nvim))
(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:nvim-orgmode/orgmode :always
     :akinsho/org-bullets.nvim {:for :org}
     :dhruvasagar/vim-table-mode {:for :org}}))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "BufEnter" 
    {:pattern "*.org"
     :group (vim.api.nvim_create_augroup "mimis-orgmode" {:clear true})
     :desc "Setup org mode"
     :callback 
     (partial 
       vim.schedule 
       (fn []
         (let [wk (require :which-key)
               og (require :orgmode)
               ob (require "org-bullets")
               buffer (vim.api.nvim_get_current_buf)]
           (og.setup {:mappings {:disable_all true}})
           (ob.setup)
           (wk.add 
             [{1 (.. nvim.g.mapleader "m") :group "org" :buffer buffer}
              {1 (.. nvim.g.mapleader "me") :group "evaluation" :buffer buffer}
              {1 (.. nvim.g.mapleader "mt") :group "tangle" :buffer buffer}])
           ;;(vim.keymap.set "n" " mee" vabel.eval-code-block  {:desc "eval-code-block"})
           ;;(vim.keymap.set "n" " mtt" vabel.tangle-blocks {:desc "tangle-file"})
           )))}))

{: enable
 : setup }
