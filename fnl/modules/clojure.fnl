(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter]
  [:modules.projects])

(fn m-binding [bind action desc]
  (mimis.leader-map
    "n"
    (.. "m" bind)
    action
    {:desc desc :buffer (vim.api.nvim_get_current_buf)}))

(fn db-binding [bind action desc]
  (m-binding (.. "d" bind) action desc))

(fn reloaded-binding [bind action desc]
  (m-binding (.. "r" bind) action desc))

(fn eval-binding [bind action desc]
  (m-binding (.. "e" bind) action desc))

(fn root-expression []
  (let [value (vim.treesitter.get_node {:ignore_injections true})]
    (when value
      (vim.treesitter.get_node_text value 0))))

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-clojure/0.0.32-1"))
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

         (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
         (m-binding "sh" r.hide-repl "hide-repl")
         (m-binding "sj" shadow-jack "hook-into-shadow-repl")
         (m-binding "sw" shadow-watch "start-shadow-build")
         (m-binding "sx" r.kill-repl "kill-repl")
         (m-binding "si" (partial r.jack-in :clojure) "jack-in")
         (m-binding "sc" ":ClojureConnect" "connect-to-running-repl")
         (m-binding "tb" test "Run buffer tests")
         (m-binding "tp" test-all "Run project tests")

         (eval-binding "e" (partial r.send root-expression) "expression-to-repl")

         (reloaded-binding "d" dev "dev")
         (reloaded-binding "g" go "reloaded-go")
         (reloaded-binding "x" reset "reloaded-reset")
         (reloaded-binding "S" stop "reloaded-stop")
         (reloaded-binding "s" system "reloaded-system")
         (reloaded-binding "r" reload "require-ns-with-reload")
         (reloaded-binding "R" reload-all "require-ns-with-reload-all")

         (db-binding "i" init-db "init-db")
         (db-binding "m" migrate-db "migrate-db")

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
