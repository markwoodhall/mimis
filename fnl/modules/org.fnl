(local nvim (require :nvim))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (plugins.register
    {:nvim-orgmode/orgmode :always
     :akinsho/org-bullets.nvim {:for :org}
     :dhruvasagar/vim-table-mode {:for :org}}))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))
        og (require :orgmode)]
    (og.setup {:mappings {:disable_all true}})

    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern :org
       :group (vim.api.nvim_create_augroup "mimis-orgmode" {:clear true})
       :desc "Setup org mode"
       :callback 
       (partial 
         vim.schedule 
         (fn []
           (let [wk (require :which-key)
                 ob (require "org-bullets")
                 buffer (vim.api.nvim_get_current_buf)]
             (ob.setup)
             (when (.  o :org-babel-like)
               (let [mimis (require :mimis)
                     vabel (require :modules.vabel)]
                 (wk.add 
                   [{1 (.. nvim.g.mapleader "m") :group "org" :buffer buffer}
                    {1 (.. nvim.g.mapleader "me") :group "evaluation" :buffer buffer}
                    {1 (.. nvim.g.mapleader "mt") :group "tangle" :buffer buffer}])
                 (mimis.leader-map "n" "mee" vabel.eval-code-block {:desc "eval-code-block" :buffer buffer})
                 (mimis.leader-map "n" "mtf" vabel.tangle-blocks {:desc "tangle-file" :buffer buffer}))))))})))

{: enable
 : setup 
 : depends }
