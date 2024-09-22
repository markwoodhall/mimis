(local plugins (require :plugins))

(fn enable []
  (plugins.register {:tpope/vim-surround :always}))

(fn setup [])

{: enable
 : setup }
