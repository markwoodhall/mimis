(fn enable [])

(fn setup []

  (vim.api.nvim_create_autocmd
    "FileType"
    {:group (vim.api.nvim_create_augroup "mimis-treesitter" {:clear true})
     :desc "Start treesitter for specific filetypes"
     :callback (fn [args] 
                 (vim.schedule 
                   (fn []
                     (when (not= vim.bo.buftype :terminal) 
                       (pcall vim.treesitter.start args.buf)))))}))

{: enable
 : setup }
