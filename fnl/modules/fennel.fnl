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

         (vim.api.nvim_create_user_command
           "Repl"
           (fn [] (r.jack-in :fennel))
           {:bang false :desc "Start repl"})

         (vim.api.nvim_create_user_command
           "Eval"
           (fn [] (r.send root-expression))
           {:bang false :desc "Eval current expression"})

         (vim.api.nvim_create_user_command
           "Reload"
           (fn [] (r.send (.. ",reload " (vim.fn.expand "%:r")) :none))
           {:bang false :desc "Reload module"}))
       (when (not lsp-setup) 
         (vim.lsp.enable :fennel_ls)
         (set lsp-setup true)))}))

{: enable 
 : setup 
 : depends }
