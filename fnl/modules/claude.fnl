(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:coder/claudecode.nvim :always}))

(fn setup []
  (let [cc (require :claudecode)]
    (cc.setup)))

{: enable
 : setup }
