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
       (mimis.leader-map "n" "ldD" ":lua vim.diagnostic.setqflist()<CR>" {:desc "project-diagnostics"})
       (mimis.leader-map "n" "ldd" ":lua vim.diagnostic.setloclist()<CR>" {:desc "buffer-diagnostics"})
       (mimis.leader-map "n" "ldr" ":lua vim.lsp.buf.references()<CR>" {:desc "references"})
       (mimis.leader-map "n" "lgd" ":lua vim.lsp.buf.definition()<CR>" {:desc "go-to-definition"})
       (mimis.leader-map "n" "lrr" ":lua vim.lsp.buf.rename()<CR>" {:desc "rename"})
       (mimis.leader-map "n" "lda" ":lua vim.lsp.buf.code_action()<CR>" {:desc "code-actions"})
       (mimis.leader-map "n" "lf" ":lua vim.lsp.buf.format()<CR>" {:desc "format-buffer"})

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
    {:desc "Complettion"
     :group (vim.api.nvim_create_augroup "mimis-lsp-completion" {:clear true})
     :callback 
     (partial 
       vim.schedule (fn [] 
                      (vim.lsp.completion.get)))}))

{: enable 
 : setup }
