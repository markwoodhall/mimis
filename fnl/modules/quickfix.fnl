(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {:kevinhwang91/nvim-bqf {:for :qf}}))

(fn setup [])

{: enable
 : setup }
