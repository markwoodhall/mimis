(local plugins (require :plugins))

(fn depends []
  [
   :modules.projects])

(fn enable []
 (plugins.register 
    {:hashivim/vim-terraform :always}))

(fn setup [])

{: enable 
 : setup 
 : depends }
