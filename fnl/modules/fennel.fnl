(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter]
  [:modules.projects])

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-fennel/0.0.37-1"))
  (plugins.register 
    {:jaawerth/fennel.vim {:for [:fennel]}}))

(fn m-binding [bind action desc]
  (mimis.leader-map
    "n"
    (.. "m" bind)
    action
    {:desc desc :buffer (vim.api.nvim_get_current_buf)}))

(fn eval-binding [bind action desc]
  (m-binding (.. "e" bind) action desc))

(fn root-expression []
  (let [value (vim.treesitter.get_node {:ignore_injections true})]
    (when value
      (vim.treesitter.get_node_text value 0))))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :fennel
     :group (vim.api.nvim_create_augroup "mimis-fennel" {:clear true})
     :desc "Setup fennel mode"
     :callback 
     (partial 
       vim.schedule 
       (fn []
         (let [r (require :modules.repl)]
           (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
           (m-binding "sh" r.hide-repl "hide-repl")
           (m-binding "sx" r.kill-repl "kill-repl")
           (m-binding "si" (partial r.jack-in :fennel) "jack-in")
           (eval-binding "e" (partial r.send root-expression :none) "expression-to-repl")
           (m-binding "rm" (partial r.send (.. ",reload " (vim.fn.expand "%:r")) :none) "reload-module"))))}))

{: enable 
 : setup 
 : depends }
