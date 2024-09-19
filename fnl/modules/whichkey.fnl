(local plugins (require :plugins))

(fn enable []
  (plugins.register {"folke/which-key.nvim" :always}))

(fn setup []
  (let [wk (require :which-key)]
    (wk.setup {:triggers [" "]})))

{: enable
 : setup }
