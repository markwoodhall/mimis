(local plugins (require :plugins))

(fn depends []
  [:modules.projects])

(fn enable []
  (plugins.register {:Julian/lean.nvim {:for :lean}}))

(fn setup [])

{: enable 
 : setup 
 : depends }
