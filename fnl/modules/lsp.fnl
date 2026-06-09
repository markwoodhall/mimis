(local ft (require :modules.filetypes))
(local mimis (require :mimis))

(var lsp-languages [])

(fn enable [languages module-hook]
  (let [languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set lsp-languages (mimis.concat lsp-languages languages))))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern lsp-languages
     :group (vim.api.nvim_create_augroup "mimis-lsp" {:clear true})
     :desc "Setup lsp for specific filetypes"
     :callback 
     (fn []
       (vim.api.nvim_create_user_command
         "Diagnostics"
         (fn [] 
           (vim.diagnostic.setloclist))
         {:bang false :desc "Diagnostics" })

       (vim.api.nvim_create_user_command
         "PDiagnostics"
         (fn [] 
           (vim.diagnostic.setqflist))
         {:bang false :desc "Project Diagnostics" })

       (vim.api.nvim_create_autocmd 
         :LspAttach
         {:desc "LSP attach"
          :group (vim.api.nvim_create_augroup "mimis-lsp-attach" {:clear true})
          :callback 
          (fn [args] 
            (when args
              (let [client (vim.lsp.get_client_by_id args.data.client_id)]
                (vim.lsp.completion.enable true args.data.client_id args.buf {:autotrigger true})
                (set client.server_capabilities.semanticTokensProvider nil))))}))})

  (vim.api.nvim_create_autocmd 
    :InsertCharPre
    {:desc "Completion"
     :group (vim.api.nvim_create_augroup "mimis-lsp-completion" {:clear true})
     :callback 
     (partial 
       vim.schedule (fn [] 
                      (vim.lsp.completion.get)))}))

{: enable 
 : setup }
