(fn enable [])

(fn setup []

  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-terraform.0.36-1"))
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
