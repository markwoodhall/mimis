(fn depends []
  [:modules.projects])

(fn enable []
  (vim.lsp.config 
    :rust-analyzer 
    {:cmd [:rust-analyzer]
     :filetypes [:rust]
     :root_markers ["cargo.toml"]}))

(var lsp-setup nil)
(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :rust
     :group (vim.api.nvim_create_augroup "mimis-rust" {:clear true})
     :desc "Setup python mode"
     :callback 
     (fn [_]
       (when (not lsp-setup) 
         (vim.lsp.enable :rust-analyzer)
         (set lsp-setup true)))}))

{: enable 
 : setup 
 : depends }
