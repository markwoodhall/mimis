(fn enable [])

;; No longer using nvim-treesitter, using luarocks to install tree sitter grammars
;; and add to runtime path
;;luarocks \
;;    --lua-version=5.5 \
;;    --tree=$HOME/.local/share/nvim/plugged/ts \
;;    install tree-sitter-sql
(fn setup []

  (vim.api.nvim_create_autocmd
    "BufWinEnter"
    {:group (vim.api.nvim_create_augroup "mimis-treesitter" {:clear true})
     :desc "Start treesitter for specific filetypes"
     :callback  (fn [args]
                  (vim.schedule 
                    (fn []
                      (when (not= vim.bo.buftype :terminal)
                        (pcall vim.treesitter.start args.buf)))))}))

{: enable
 : setup }
