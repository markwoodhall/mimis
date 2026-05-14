(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {:kevinhwang91/nvim-bqf :always}))

(fn setup []
  (let [bqf (require :bqf)]
    (bqf.setup {:preview {:border nvim.o.winborder}})))

{: enable
 : setup }
