(local plugins (require :plugins))

(fn depends []
  [:modules.projects])

(fn enable []
  (plugins.register 
    {:jaawerth/fennel.vim {:for [:fennel]}})
  (vim.lsp.config 
    :fennel_ls 
    {:cmd [:fennel-ls]
     :filetypes [:fennel]
     :root_markers ["flsproject.fnl"]}))

(fn eval-opfunc [mtype]
  (let [sel (if (= mtype "line") "V" "v")
        r (require :modules.repl)]
    (vim.cmd (.. "normal! `[" sel "`]y"))
    (r.send (vim.fn.getreg "\"") :none)))

(global EvalOpfunc eval-opfunc)

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
           (fn [opts] (r.jack-in opts :fennel))
           {:bang false :desc "Start repl"})

         (vim.keymap.set :n "Q"
                         #(do (set vim.o.operatorfunc "v:lua.EvalOpfunc") "g@")
                         {:expr true :buffer true :desc "Eval (operator)"})

         (vim.keymap.set :n "QQ"
                         #(do (set vim.o.operatorfunc "v:lua.EvalOpfunc") "g@_")
                         {:expr true :buffer true :desc "Eval line"})

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
