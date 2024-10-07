(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {:lukas-reineke/indent-blankline.nvim :always}))

(fn setup []
  (let [ibl (require :ibl)]
    (ibl.setup)))

{: enable
 : setup }
