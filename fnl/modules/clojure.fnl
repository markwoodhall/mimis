(local nvim (require "nvim"))
(local mimis (require :mimis))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter 
   :modules.projects])

(fn root-expression []
  (let [value (vim.treesitter.get_node {:ignore_injections true})]
    (when value
      (vim.treesitter.get_node_text value 0))))

(fn enable []
  (mimis.try-add-treesitter-path :clojure "0.0.32-1")
  (plugins.register {:clojure-vim/clojure.vim {:for :clojure}})
  (vim.lsp.config 
    :clojure_lsp 
    {:cmd [:clojure-lsp]
     :filetypes [:clojure]
     :root_markers ["project.clj" "deps.edn" "build.boot" "shadow-cljs.edn" "bb.edn"]}))

(var lsp-setup nil)

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
             dev (partial r.send "(dev)" :user)
             go (partial r.send "(go)" :dev)
             reset (partial r.send "(reset)" :dev)
             stop (partial r.send  "(stop)" :dev)
             system (partial r.send "@system")
             reload (partial 
                      r.send 
                      (fn [] (.. "(clojure.core/require '" (r.current-ns) " :reload)"))
                      :current)
             reload-all (partial 
                          r.send 
                          (fn [] (.. "(clojure.core/require '" (r.current-ns) " :reload-all)"))
                          (r.current-ns))
             test (partial 
                    r.send
                    (fn [] (.. "(clojure.test/run-tests '" (r.current-ns) ")"))
                    :current)
             test-all (partial 
                        r.send
                        "(clojure.test/run-all-tests)"
                        :current)
             init-db (partial r.send "(use 'db) (db/init-schema)" :dev)
             migrate-db (partial r.send  "(use 'db) (db/migrate-schema)" :dev)
             shadow-jack (partial r.send "(shadow/repl :app)" :none)
             shadow-watch (partial r.send "(shadow/watch :app)" :none)]

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
           "Repl"
           (partial r.jack-in :clojure)
           {:bang false :desc "Start repl"})

         (vim.api.nvim_create_user_command
           "Test"
           test-all
           {:bang true :desc "Run project tests"})

         (vim.api.nvim_create_user_command
           "Test"
           test
           {:bang false :desc "Run buffer tests"})

         (vim.api.nvim_create_user_command
           "Eval"
           (partial r.send root-expression)
           {:bang false :desc "Eval current expression"})

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
           reload
           {:bang false :desc "Require namespace"})

         (vim.api.nvim_create_user_command
           "Require"
           reload-all
           {:bang true :desc "Require namespace with reload-all"})

         (vim.api.nvim_create_user_command
           "InitDb"
           init-db
           {:bang false :desc "Ragtime init-db"})

         (vim.api.nvim_create_user_command
           "MigrateDb"
           migrate-db
           {:bang false :desc "Ragtime migrate-db"})

         (vim.api.nvim_create_user_command
           "ClojureConnect"
           (fn [opts]
             (let [args (accumulate 
                          [s ""
                           _ v (ipairs (?. opts :fargs))]
                          (.. s " " v))]
               (r.connect-in :clojure args)))
           {:bang false :desc "Connect to repl" :nargs "*"})

         (when (not lsp-setup) 
           (vim.lsp.enable :clojure_lsp)
           (set lsp-setup true))))}))

{: depends
 : enable
 : setup }
