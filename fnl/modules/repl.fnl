(local mimis (require :mimis))

(local repl {:repls {} })

(fn project-has-repl []
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (and (. repl :repls path)
         (not= (. repl :repls path) nil))))

(fn get-project-repl []
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (if (and (. repl :repls path)
             (not= (. repl :repls path) nil))
      (. repl :repls path)
      (let [buf (vim.api.nvim_create_buf true true)
            r {:last-ns nil
               :buf buf}]
        (set (. repl :repls path) r)
        (. repl :repls path))))) 

(fn set-project-repl [v]
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (set (. repl :repls path) v)))

(fn kill-project-repl []
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (set (. repl :repls path) nil)))

(fn current-ns []
  "("
    (mimis.first 
      (mimis.split (mimis.second (vim.fn.split (vim.fn.getline 1) " ")) ")")))

(fn in-ns [start-ns]
  (let [r (get-project-repl)]
    (when r
      (let [ns (or start-ns (current-ns))]
        (when (and ns (not= r.last-ns ns))
          (r.repl.quiet-send (.. "(in-ns '" ns ")"))
          (set r.last-ns ns)
          (set-project-repl r))))))

(fn show-repl [enter]
  (if (project-has-repl)
    (let [r (get-project-repl)]
      (mimis.buff r.opts r.buf)
      (when enter
        (vim.cmd.normal "G"))
      (set-project-repl r))
    (print "No repl started, please start.")))

(fn kill-repl []
  (let [r (get-project-repl)]
    (when r.repl
      (show-repl true))
    (vim.cmd ":bd!")
    (kill-project-repl)))

(fn send [expression ns]
  (let [r (get-project-repl)
        e (if (= (type expression) "string") expression (expression))]
    (if (and r r.repl r.buf)
      (do
        (when (not= :none ns)
          (if (or (not ns)
                  (= :current ns))
            (in-ns)
            (in-ns ns)))
        ((. r.repl :send) e))
      (print "Repl not connected"))))

(fn get-command [filetype]
  (case filetype
    :fennel
    (let [root (vim.fn.call "FindRootDirectory" [])]
      (if (mimis.exists? (.. root "/.mimis.repl.fennel"))
        (?. (vim.fn.readfile (.. root "/.mimis.repl.fennel")) 1)
        :fennel))
    :lisp "rlwrap sbcl"
    :clojure 
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          shadow-cljs (mimis.exists? (.. root "/shadow-cljs.edn"))
          deps-edn  (mimis.exists? (.. root "/deps.edn"))]
      (case [project-clj shadow-cljs deps-edn]
        [true false false] "lein update-in :dependencies conj \\[nrepl/nrepl\\ \\\"1.5.1\\\"\\] -- update-in :plugins     conj \\[cider/cider-nrepl\\ \\\"0.58.0\\\"\\] -- repl"
        [false true false] "npx shadow-cljs clj-repl"
        [false false true] "clojure -A:dev:dev/nrepl"
        _ "lein repl"))))

(fn visible? [buf]
  (not= -1 (vim.fn.bufwinid buf)))  

(fn ensure-shown [r]
  (when (and r.buf (not (visible? r.buf)))
    (mimis.buff r.opts r.buf)
    (set-project-repl r)))

(fn sender [r job show data]
  (vim.schedule
    (fn []
      (if r.buf
        (when data
          (vim.fn.chansend job (.. data "\n"))
          (set-project-repl r)
          (when show (ensure-shown r)))
        (print "Repl not connected")))))

(fn connect-repl [filetype connection]
  (let [r (get-project-repl)]
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          command (when project-clj (.. "lein repl :connect " connection))
          job (when command (vim.fn.jobstart command {:term true}))]
      (if job 
        (do
          (set vim.bo.filetype filetype)
          {:job job
           :quiet-send (partial sender r job false)
           :send (partial sender r job true)})
        (print "Cannot find a repl type to connect to for this project")))))

(fn start-repl [filetype]
  (let [r (get-project-repl)]
    (let [command (get-command filetype)
          job (vim.fn.jobstart command {:term true})]
      (set vim.bo.filetype filetype)
      {:job job
       :quiet-send (partial sender r job false)
       :send (partial sender r job true)})))

(fn jack-in [opts filetype]
  (let [r (get-project-repl)]
    (set r.opts opts)
    (show-repl true)
    (when (not r.repl) (set r.repl (start-repl filetype)))
    (set-project-repl r)))

(fn connect-in [opts filetype connection-str]
  (let [r (get-project-repl)]
    (set r.opts opts)
    (show-repl true)
    (when (not r.repl) (set r.repl (connect-repl filetype connection-str)))
    (set-project-repl r)))

(vim.api.nvim_create_user_command
  "ReplKill"
  kill-repl
  {:bang false :desc "Kill repl"})

{: current-ns
 : in-ns
 : kill-repl
 : jack-in
 : connect-in
 : send }
