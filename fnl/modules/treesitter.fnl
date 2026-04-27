(local plugins (require :plugins))
(local ft (require :modules.filetypes))

(var treesitter-languages [])
(var treesitter-parsers [:markdown :markdown_inline])
(var treesitter-configured nil)

(fn enable [languages module-hook]
  (let [mimis (require :mimis)
        languages (or languages
                      (. ft.module-filetypes module-hook)
                      [])]
    (set treesitter-languages (mimis.concat treesitter-languages languages))
    (plugins.register {:nvim-treesitter/nvim-treesitter {:branch "main" :do ":TSUpdate"}})))

(local module-parsers ft.module-filetypes)

(local ignore-install {:org true})

(fn install-parsers []
  (let [nts (require :nvim-treesitter)
        to-install (icollect [_ p (ipairs treesitter-parsers)]
                     (when (not (. ignore-install p)) p))]
    (when (not treesitter-configured)
      (nts.setup)
      (set treesitter-configured true))
    (when (> (length to-install) 0)
      (nts.update to-install))))

(fn setup [parsers module-hook]
  (let [mimis (require :mimis)
        parsers (or parsers
                    (. module-parsers module-hook)
                    [])]
    (set treesitter-parsers (mimis.concat treesitter-parsers parsers))
    (install-parsers)
    (vim.api.nvim_create_autocmd
      "FileType"
      {:pattern treesitter-languages
       :group (vim.api.nvim_create_augroup "mimis-treesitter" {:clear true})
       :desc "Start treesitter for specific filetypes"
       :callback (fn [args]
                   (pcall vim.treesitter.start args.buf))})))

{: enable
 : setup }