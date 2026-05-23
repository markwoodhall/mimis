(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (mimis.try-add-treesitter-path :sql "0.0.55-1"))

(fn setup [])

{: enable
 : setup 
 : depends }
