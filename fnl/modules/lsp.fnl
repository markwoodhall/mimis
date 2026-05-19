(local plugins (require :plugins))
(local ft (require :modules.filetypes))
(local nvim (require :nvim))

(var lsp-languages [])
(var lsp-servers [])
(var lsp-setup-done nil)

(fn enable [languages module-hook]
  (let [mimis (require :mimis)
        languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set lsp-languages (mimis.concat lsp-languages languages))
    (plugins.register
      {:neovim/nvim-lspconfig {:for lsp-languages}})))

(fn setup-cmp [servers]
  (each [_ server (pairs servers)]
    (vim.lsp.enable server)))

(local fennel {:servers [:fennel_ls]})
(local clojure {:servers [:clojure_lsp]})
(local terraform {:servers [:terraform_lsp]})
(local sql {:servers [:sqlls]})

(local setup-hooks
  {:modules.packages.fennel fennel
   :modules.packages.clojure clojure
   :modules.packages.sql sql
   :modules.clojure clojure
   :modules.fennel fennel
   :modules.terraform terraform
   :modules.sql sql})

(fn setup [options module-hook]
  (let [mimis (require :mimis)
        servers (or (if options options.servers nil)
                               (. (. setup-hooks module-hook) :servers)
                               []) ]
    (set lsp-servers (mimis.concat lsp-servers servers))
    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern lsp-languages
       :group (vim.api.nvim_create_augroup "mimis-lsp" {:clear true})
       :desc "Setup lsp for specific filetypes"
       :callback 
       (partial 
         vim.schedule 
         (fn []
           (when (not lsp-setup-done)
             (setup-cmp lsp-servers)
             (let [mimis (require :mimis)]
               (mimis.leader-map "n" "ldD" ":lua vim.diagnostic.setqflist()<CR>" {:desc "project-diagnostics"})
               (mimis.leader-map "n" "ldd" ":lua vim.diagnostic.setloclist()<CR>" {:desc "buffer-diagnostics"})
               (mimis.leader-map "n" "ldr" ":lua vim.lsp.buf.references()<CR>" {:desc "references"})
               (mimis.leader-map "n" "lgd" ":lua vim.lsp.buf.definition()<CR>" {:desc "go-to-definition"})
               (mimis.leader-map "n" "lrr" ":lua vim.lsp.buf.rename()<CR>" {:desc "rename"})
               (mimis.leader-map "n" "lda" ":lua vim.lsp.buf.code_action()<CR>" {:desc "code-actions"})
               (mimis.leader-map "n" "lf" ":lua vim.lsp.buf.format()<CR>" {:desc "format-buffer"}))
             (let [wk (require :which-key)] 
               (wk.add 
                 [{1 (.. nvim.g.mapleader "l") :group "lsp"}
                  {1 (.. nvim.g.mapleader "lr") :group "refactor"}
                  {1 (.. nvim.g.mapleader "ld") :group "diagnostics"}
                  {1 (.. nvim.g.mapleader "lg") :group "goto"}]))
             (set lsp-setup-done true))))})

    (vim.api.nvim_create_autocmd 
      :LspAttach
      {:desc "LSP attach"
       :group (vim.api.nvim_create_augroup "mimis-lsp-attach" {:clear true})
       :callback 
       (fn [args] 
         (when args
           (let [client (vim.lsp.get_client_by_id args.data.client_id)]
             (vim.lsp.completion.enable true args.data.client_id args.buf {:autotrigger true})
             (set client.server_capabilities.semanticTokensProvider nil))))})

    (vim.api.nvim_create_autocmd 
      :InsertCharPre
      {:desc "Complettion"
       :group (vim.api.nvim_create_augroup "mimis-lsp-completion" {:clear true})
       :callback 
       (partial 
         vim.schedule (fn [] 
                        (vim.lsp.completion.get)))})

    (vim.api.nvim_create_autocmd 
      ["BufWritePre"] 
      {:pattern "*.*"
       :group (vim.api.nvim_create_augroup "mimis-lsp-formatting" {:clear true})
       :desc "LSP format on save"
       :callback 
       (partial 
         vim.schedule 
         (fn [] 
           (when (vim.lsp.buf_is_attached)
             (vim.lsp.buf.format))))})))

{: enable 
 : setup }
