(local plugins (require :plugins))
(local nvim (require :nvim))
(var lsp-languages [])
(var lsp-setup-done nil)

(fn enable [languages]
  (plugins.register
    {:neovim/nvim-lspconfig {:for languages} 
     :hrsh7th/nvim-cmp {:for languages} 
     :hrsh7th/cmp-nvim-lsp {:for languages} 
     :hrsh7th/cmp-path {:for languages}})
  (set lsp-languages languages))

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

(fn setup [servers completion-sources]
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
           (setup-cmp servers)
           (let [mimis (require :mimis)]
             (mimis.leader-map "n" "ldD" ":Telescope diagnostics<CR>" {:desc "project-diagnostics"})
             (mimis.leader-map "n" "ldd" ":Telescope diagnostics bufnr=0<CR>" {:desc "buffer-diagnostics"})
             (mimis.leader-map "n" "ldr" ":Telescope lsp_references<CR>" {:desc "references"})
             (mimis.leader-map "n" "lda" ":lua vim.lsp.buf.code_action()<CR>" {:desc "code-actions"})
             (mimis.leader-map "n" "lf" ":lua vim.lsp.buf.format()<CR>" {:desc "format-buffer"})
             (mimis.leader-map "n" "lgd" ":Telescope lsp_definitions<CR>" {:desc "go-to-definition"}))
           (let [wk (require :which-key)] 
             (wk.add 
               [{1 (.. nvim.g.mapleader "l") :group "lsp"}
                {1 (.. nvim.g.mapleader "ld") :group "diagnostics"}
                {1 (.. nvim.g.mapleader "lg") :group "goto"}]))
           (set lsp-setup-done true))
         (vim.cmd.LspStart)))})

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
    (icollect [k v (pairs completion-sources)]
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
                   {:sources (cmp.config.sources v)}))))})))))

{: enable 
 : setup }
