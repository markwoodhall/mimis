(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter
   :modules.projects])

(fn enable []
  (mimis.try-add-treesitter-path :hcl "0.0.35-1")
  (vim.treesitter.language.register :hcl [:terraform]))

(fn setup [])

{: enable 
 : setup 
 : depends }
