(local mimis (require :mimis))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter 
   :modules.projects])

(fn enable []
  (mimis.try-add-treesitter-path :fennel "0.0.37-1")
  (plugins.register 
    {:jaawerth/fennel.vim {:for [:fennel]}})
  (vim.lsp.config 
    :fennel_ls 
    {:cmd [:fennel-ls]
     :filetypes [:fennel]
     :root_markers ["flsproject.fnl"]}))

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

(var lsp-setup nil)
(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :fennel
     :group (vim.api.nvim_create_augroup "mimis-fennel" {:clear true})
     :desc "Setup fennel mode"
     :callback 
     (fn [_]
       (let [r (require :modules.repl)]
         (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
         (m-binding "sh" r.hide-repl "hide-repl")
         (m-binding "sx" r.kill-repl "kill-repl")
         (m-binding "si" (partial r.jack-in :fennel) "jack-in")
         (eval-binding "e" (partial r.send root-expression :none) "expression-to-repl")
         (m-binding "rm" (partial r.send (.. ",reload " (vim.fn.expand "%:r")) :none) "reload-module"))
       (when (not lsp-setup) 
         (vim.lsp.enable :fennel_ls)
         (set lsp-setup true)))}))

{: enable 
 : setup 
 : depends }
