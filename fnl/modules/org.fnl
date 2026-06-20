(fn depends [])

(fn enable [])

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))]
    (when (. o :notes)
      (require :modules.notes))
    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern :org
       :group (vim.api.nvim_create_augroup "mimis-orgmode" {:clear true})
       :desc "Setup org mode"
       :callback 
       (fn []
         (when (.  o :org-babel-like)
           (let [vabel (require :modules.vabel)]
             (vim.cmd "syntax sync minlines=400")
             (vim.api.nvim_create_user_command
               "Tangle"
               vabel.tangle-blocks
               {:bang false :desc "Tangle file"})

             (vim.api.nvim_create_user_command
               "Eval"
               vabel.eval-code-block
               {:bang false :desc "Eval current block"}))))})))

{: enable
 : setup 
 : depends }
