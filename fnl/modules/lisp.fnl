(fn depends []
  [:modules.projects
   :modules.paredit])

(fn enable [])

(fn eval-opfunc [mtype]
  (let [sel (if (= mtype "line") "V" "v")
        r (require :modules.repl)]
    (vim.cmd (.. "normal! `[" sel "`]y"))
    (r.send (vim.fn.getreg "\"") :none)))

(global LispEvalOpfunc eval-opfunc)

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern [:lisp]
     :group (vim.api.nvim_create_augroup "mimis-lisp" {:clear true})
     :desc "Setup lisp mode"
     :callback 
     (fn []
       (let [r (require :modules.repl)]
         (vim.api.nvim_buf_create_user_command
           "Repl"
           (fn [opts] (r.jack-in opts :lisp))
           {:bang false :desc "Start repl"})

         (vim.keymap.set :n "Q"
                         #(do (set vim.o.operatorfunc "v:lua.LispEvalOpfunc") "g@")
                         {:expr true :buffer true :desc "Eval (operator)"})

         (vim.keymap.set :n "QQ"
                         #(do (set vim.o.operatorfunc "v:lua.LispEvalOpfunc") "g@_")
                         {:expr true :buffer true :desc "Eval line"})))}))

{: depends
 : enable
 : setup }
