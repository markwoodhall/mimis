(local plugins (require :plugins))
(local ft (require :modules.filetypes))
(local nvim (require :nvim))

(var lsp-languages [])
(var lsp-completion-sources [])
(var lsp-servers [])
(var lsp-setup-done nil)

(fn enable [languages module-hook]
  (let [mimis (require :mimis)
        languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set lsp-languages (mimis.concat lsp-languages languages))
    (plugins.register
      {:neovim/nvim-lspconfig {:for lsp-languages} 
       :hrsh7th/nvim-cmp {:for lsp-languages} 
       :hrsh7th/cmp-nvim-lsp {:for lsp-languages} 
       :hrsh7th/cmp-path {:for lsp-languages}})))

(fn setup-cmp [servers]
  (let [cmp-nvim-lsp (require :cmp_nvim_lsp)
        lsp-config (require :lspconfig)
        cmp (require :cmp)
        capabilities (cmp-nvim-lsp.default_capabilities)]
    (each [_ server (pairs servers)]
      (let [config (. lsp-config server)]
        (case server
          _ (config.setup {:autostart false
                           :capabilities capabilities}))))

    (cmp.setup
      {:mapping (cmp.mapping.preset.insert
                  {"<C-u>" (cmp.mapping.scroll_docs -4)
                   "<C-d>" (cmp.mapping.scroll_docs 4)
                   "<C-Space>" (cmp.mapping.complete)
                   "<CR>" (cmp.mapping.confirm {:behavior cmp.ConfirmBehavior.Replace :select true})
                   "<C-j>" (cmp.mapping (fn [fallback]
                                          (if (cmp.visible)
                                            (cmp.select_next_item)
                                            (fallback)))
                                        ["i" "s"])
                   "<C-k>" (cmp.mapping (fn [fallback]
                                          (if (cmp.visible)
                                            (cmp.select_prev_item)
                                            (fallback)))
                                        ["i" "s"])})
       :sources [{:name "nvim_lsp" :keyword_length 1}
                 {:name "path" :keyword_length 3}
                 {:name "buffer" :keyword_length 4}]})))

(local fennel {:servers [:fennel_ls]
               :completion-sources
               {:fennel [{:name "nvim_lsp" :keyword_length 2}
                         {:name "buffer" :keyword_length 2}]}})

(local clojure {:servers [:clojure_lsp]
                :completion-sources
                {:clojure [{:name "nvim_lsp" :keyword_length 2}
                           {:name "buffer" :keyword_length 2}]}})

(local sql {:servers [:sqlls]})

(local setup-hooks
  {:modules.packages.fennel fennel
   :modules.packages.clojure clojure
   :modules.packages.sql sql
   :modules.clojure clojure
   :modules.fennel fennel
   :modules.sql sql})

(fn setup [options module-hook]
  (let [mimis (require :mimis)
        completion-sources (or (if options options.completion-sources nil)
                               (. (. setup-hooks module-hook) :completion-sources)
                               [])
        servers (or (if options options.servers nil)
                               (. (. setup-hooks module-hook) :servers)
                               [])]
    (set lsp-servers (mimis.concat lsp-servers servers))
    (set lsp-completion-sources (mimis.concat lsp-completion-sources completion-sources))
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
               (mimis.leader-map "n" "lrr" ":lua vim.lsp.buf.rename()<CR>" {:desc "rename"})
               (mimis.leader-map "n" "lda" ":lua vim.lsp.buf.code_action()<CR>" {:desc "code-actions"})
               (mimis.leader-map "n" "lf" ":lua vim.lsp.buf.format()<CR>" {:desc "format-buffer"}))
             (let [wk (require :which-key)] 
               (wk.add 
                 [{1 (.. nvim.g.mapleader "l") :group "lsp"}
                  {1 (.. nvim.g.mapleader "lr") :group "refactor"}
                  {1 (.. nvim.g.mapleader "ld") :group "diagnostics"}
                  {1 (.. nvim.g.mapleader "lg") :group "goto"}]))
             (set lsp-setup-done true))
           (vim.cmd.LspStart)))})

    (vim.api.nvim_create_autocmd 
      :LspAttach
      {:desc "LSP disable semantic tokens"
       :callback 
       (fn [args] 
         (let [client (vim.lsp.get_client_by_id args.data.client_id)]
           (set client.server_capabilities.semanticTokensProvider nil)))})

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
             (vim.lsp.buf.format))))})

    (let [group (vim.api.nvim_create_augroup "mimis-lsp-filetype" {:clear true})]
      (icollect [k v (pairs lsp-completion-sources)]
        (do
          (vim.api.nvim_create_autocmd 
            "FileType" 
            {:pattern k
             :group group
             :desc "Setup lsp completion sources for specific filetypes"
             :callback 
             (partial 
               vim.schedule 
               (fn []
                 (let [cmp (require :cmp)]
                   (cmp.setup.filetype 
                     k
                     {:sources (cmp.config.sources v)}))))}))))))

{: enable 
 : setup }
