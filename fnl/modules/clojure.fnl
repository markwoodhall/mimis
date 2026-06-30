(local nvim (require "nvim"))
(local mimis (require :mimis))
(local plugins (require :plugins))

(fn depends []
  [:modules.projects])

(fn enable []
  (plugins.register {:clojure-vim/clojure.vim {:for :clojure}})
  (vim.lsp.config 
    :clojure_lsp 
    {:cmd [:clojure-lsp]
     :filetypes [:clojure]
     :root_markers ["project.clj" "deps.edn" "build.boot" "shadow-cljs.edn" "bb.edn"]}))

(var lsp-setup nil)

(fn esc [s]
  (-> s
      (string.gsub "\\" "\\\\")
      (string.gsub "\"" "\\\"")))

(fn eval-opfunc [mtype]
  (let [sel (if (= mtype "line") "V" "v")
        r (require :modules.repl)]
    (vim.cmd (.. "normal! `[" sel "`]y"))
    (case (r.get-command :clojure)
      "bb" (r.send (vim.fn.getreg "\"") :clojure)
       _ (r.send (.. "(binding [*ns* (the-ns '" (r.current-ns) ")] (eval (read-string \"" (esc (vim.fn.getreg "\"")) "\")))" ) :clojure))))

(global CljEvalOpfunc eval-opfunc)

(fn setup []
  (set vim.g.clojure_max_lines 1000)
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :clojure
     :group (vim.api.nvim_create_augroup "mimis-clojure" {:clear true})
     :desc "Setup clojure mode"
     :callback 
     (fn []
       (let [r (require :modules.repl)
             dev (fn [] (r.send "(dev)" :clojure))
             go (fn [] (r.send "(use 'dev)(dev/go)" :clojure))
             reset (fn [] (r.send "(use 'dev)(dev/reset)" :clojure))
             stop (fn [] (r.send "(use 'dev)(dev/stop)" :clojure))
             system (fn [] (r.send "(use 'dev) dev/@system" :clojure))
             reload (fn [] 
                      (r.send 
                        (fn [] (.. "(clojure.core/require '" (r.current-ns) " :reload)"))
                        :clojure))
             reload-all (fn [] 
                          (r.send 
                            (fn [] (.. "(clojure.core/require '" (r.current-ns) " :reload-all)"))
                            :clojure))
             test (fn [] 
                    (r.send
                      (fn [] (.. "(clojure.test/run-tests '" (r.current-ns) ")"))
                      :clojure))
             test-all (fn [] 
                        (r.send
                          "(clojure.test/run-all-tests)" :clojure))
             init-db (fn [] (r.send "(use 'db) (db/init-schema)" :clojure))
             migrate-db (fn [] (r.send  "(use 'db) (db/migrate-schema)" :clojure))
             shadow-jack (fn [] (r.send "(shadow/repl :app)" :clojure))
             shadow-watch (fn [] (r.send "(shadow/watch :app)" :clojure))]

         (set nvim.bo.suffixesadd ".clj,.cljs,.cljc,.edn")
         (set nvim.bo.includeexpr "substitute(substitute(v:fname,'\\.', '/', 'g'), '-', '_', 'g')")

         (vim.api.nvim_create_user_command
           "ShadowJack"
           shadow-jack
           {:bang false :desc "Jack into shadow repl"})

         (vim.api.nvim_create_user_command
           "ShadowWatch"
           shadow-watch
           {:bang false :desc "Start shadow watch"})

         (vim.api.nvim_create_user_command
           "Load"
           (fn []
             (r.send (.. "(load-file \"" (vim.fn.expand "%") "\")") :clojure))
           {:bang true :desc "Start repl"})

         (vim.api.nvim_buf_create_user_command
           0
           "Repl"
           (fn [opts]
             (let [root (vim.fn.call "FindRootDirectory" [])
                   shadow-cljs (mimis.exists? (.. root "/shadow-cljs.edn"))]
               (r.jack-in opts :clojure)
               (when opts.bang
                 (if shadow-cljs
                   (do 
                     (shadow-watch)
                     (shadow-jack))
                   (do 
                     (dev)
                     (go))))))
           {:bang true :desc "Start repl"})

         (vim.api.nvim_create_user_command
           "Test"
           test-all
           {:bang true :desc "Run project tests"})

         (vim.api.nvim_create_user_command
           "Test"
           test
           {:bang false :desc "Run buffer tests"})

         (vim.keymap.set :n "Q"
                         #(do (set vim.o.operatorfunc "v:lua.CljEvalOpfunc") "g@")
                         {:expr true :buffer true :desc "Eval (operator)"})

         (vim.keymap.set :n "QQ"
                         #(do (set vim.o.operatorfunc "v:lua.CljEvalOpfunc") "g@_")
                         {:expr true :buffer true :desc "Eval line"})

         (vim.api.nvim_create_user_command
           "Dev"
           dev
           {:bang false :desc "Clojure dev namespace"})

         (vim.api.nvim_create_user_command
           "System"
           system
           {:bang false :desc "Reloaded system"})

         (vim.api.nvim_create_user_command
           "Reset"
           reset
           {:bang false :desc "Reloaded reset"})

         (vim.api.nvim_create_user_command
           "Go"
           go
           {:bang false :desc "Reloaded go"})

         (vim.api.nvim_create_user_command
           "Stop"
           stop
           {:bang false :desc "Reloaded stop"})

         (vim.api.nvim_create_user_command
           "Require"
           (fn [opts] 
             (if opts.bang (reload-all) (reload)))
           {:bang true :desc "Require namespace (! to reload all)"})

         (vim.api.nvim_create_user_command
           "InitDb"
           init-db
           {:bang false :desc "Ragtime init-db"})

         (vim.api.nvim_create_user_command
           "MigrateDb"
           migrate-db
           {:bang false :desc "Ragtime migrate-db"})

         (vim.api.nvim_create_user_command
           "Doc"
           (fn [opts] (r.send  (.. "(clojure.repl/doc " (mimis.first opts.fargs) ")") :clojure))
           {:bang false :desc "Clojure (doc ..)" :nargs 1})

         (vim.api.nvim_create_user_command
           "Source"
           (fn [opts] (r.send  (.. "(clojure.repl/source " (mimis.first opts.fargs) ")" :clojure)))
           {:bang false :desc "Clojure (source ..)" :nargs 1})

         (vim.api.nvim_create_user_command
           "Apropos"
           (fn [opts] (r.send  (.. "(clojure.repl/apropos " (mimis.first opts.fargs) ")" :clojure)))
           {:bang false :desc "Clojure (apropos ..)" :nargs 1})

         (vim.api.nvim_create_user_command
           "ClojureConnect"
           (fn [opts]
             (let [args (accumulate 
                          [s ""
                           _ v (ipairs (?. opts :fargs))]
                          (.. s " " v))]
               (r.connect-in args)))
           {:bang false :desc "Connect to repl" :nargs "*"})

         (when (not lsp-setup) 
           (vim.lsp.enable :clojure_lsp)
           (set lsp-setup true))))}))

{: depends
 : enable
 : setup }
