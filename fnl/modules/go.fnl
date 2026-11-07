(local plugins (require :plugins))

(fn depends []
  [:modules.projects])

(fn enable []
  (vim.lsp.config 
    :gopls 
    {:cmd [:gopls]
     :filetypes [:go]
     :root_markers ["go" "gomod" "gowork" "gotmpl"]}))

(var lsp-setup nil)
(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :go
     :group (vim.api.nvim_create_augroup "mimis-go" {:clear true})
     :desc "Setup go mode"
     :callback 
     (fn [_]
       (when (not lsp-setup) 
         (vim.lsp.enable :gopls)
         (set lsp-setup true)))}))

{: enable 
 : setup 
 : depends }
