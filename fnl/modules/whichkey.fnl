(local Plug (. vim.fn "plug#"))

(fn enable []
  (Plug "folke/which-key.nvim"))

(fn setup []
  (let [wk (require :which-key)]
    (wk.setup {:triggers [" "]})))

{: enable
 : setup }
