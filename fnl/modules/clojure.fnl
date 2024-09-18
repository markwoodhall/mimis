(local mimis (require :mimis))
(local nvim (require "nvim"))
(local Plug (. vim.fn "plug#"))

(fn m-binding [bind action desc]
  (mimis.leader-map
    "n"
    (.. "m" bind)
    action
    {:desc desc}))

(fn db-binding [bind action desc]
  (m-binding (.. "d" bind) action desc))

(fn reloaded-binding [bind action desc]
  (m-binding (.. "r" bind) action desc))

(fn eval-binding [bind action desc]
  (m-binding (.. "e" bind) action desc))

(fn root-expression []
  (let [ts-utils (require "nvim-treesitter.ts_utils")
        value (ts-utils.get_node_at_cursor 0 true)
        data (vim.treesitter.get_node_text value 0)]
    data))

(fn enable []
  (Plug "clojure-vim/clojure.vim" {:for :clojure})
  (set vim.g.clojure_max_lines 1000))

(fn setup []
  (vim.cmd "set wildignore+=**/resources/public/js/compiled/**")
  (vim.cmd "set wildignore+=**/.clj-kondo/**")
  (vim.cmd "set wildignore+=**/cljs-test-runner-out/**")
  (vim.cmd "set wildignore+=.shadow-cljs/**")
  (vim.cmd "set wildignore+=**/deployment-temp/**")
  (vim.cmd "set wildignore+=**/target/**")
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
                          (fn [] (.. "(clojure.core/require '" (r.current-ns) " :reload)"))
                          (r.current-ns))
             test (partial 
                    r.send
                    (fn [] (.. "(clojure.test/run-tests '" (r.current-ns) ")"))
                    :current)
             test-all (partial 
                        r.send
                        "(clojure.test/run-all-tests)"
                        :current)
             init-db (partial r.send (.. "(use 'db) (db/init-schema)") :dev)
             migrate-db (partial r.send (.. "(use 'db) (db/migrate-schema)") :dev)
             shadow-jack (partial r.send "(shadow/repl :app)" :dev)
             shadow-watch (partial r.send "(shadow/watch :app)" :dev)]


         (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
         (m-binding "sh" r.hide-repl "hide-repl")
         (m-binding "sj" shadow-jack "hook-into-shadow-repl")
         (m-binding "sw" shadow-watch "start-shadow-build")
         (m-binding "sx" r.kill-repl "kill-repl")
         (m-binding "si" (partial r.jack-in :clojure) "jack-in")
         (m-binding "sc" "ClojureConnect" "connect-to-running-repl")
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

         (let [wk (require :which-key)] 
           (wk.add 
             [{1 (.. nvim.g.mapleader "m") :group "clojure"}
              {1 (.. nvim.g.mapleader "ms") :group "sesman"}
              {1 (.. nvim.g.mapleader "mr") :group "reloaded"}
              {1 (.. nvim.g.mapleader "mt") :group "tests"}
              {1 (.. nvim.g.mapleader "md") :group "ragtime"}
              {1 (.. nvim.g.mapleader "me") :group "evaluation"}]))

         (vim.api.nvim_create_user_command
           "ClojureConnect"
           (fn [opts]
             (let [args (accumulate 
                          [s ""
                           _ v (ipairs (?. opts :fargs))]
                          (.. s " " v))]
               (r.connect-in :clojure args)))
           {:bang false :desc "Connect to repl" :nargs "*"})))}))

{: enable
 : setup }