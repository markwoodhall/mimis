(local mimis (require :mimis))

(fn depends []
  [:modules.projects])

(fn enable [])

(fn eval-opfunc [mtype]
  (let [sel (if (= mtype "line") "V" "v")
        r (require :modules.repl)]
    (vim.cmd (.. "normal! `[" sel "`]y"))
    (r.send (vim.fn.getreg "\"") :sql)))

(global SqlEvalOpfunc eval-opfunc)

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :sql
     :group (vim.api.nvim_create_augroup "mimis-sql" {:clear true})
     :desc "Setup sql mode"
     :callback 
     (fn []
       (let [r (require :modules.repl)]

         (vim.keymap.set :n "Q"
                         #(do (set vim.o.operatorfunc "v:lua.SqlEvalOpfunc") "g@")
                         {:expr true :buffer true :desc "Eval (operator)"})

         (vim.keymap.set :n "QQ"
                         #(do (set vim.o.operatorfunc "v:lua.SqlEvalOpfunc") "g@_")
                         {:expr true :buffer true :desc "Eval line"})

         (vim.api.nvim_buf_create_user_command
           0
           "Repl"
           (fn [opts]
             (r.jack-in opts :sql))
           {:bang true :desc "Start repl"})))}))

{: enable
 : setup 
 : depends }
