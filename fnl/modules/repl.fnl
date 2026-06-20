(local mimis (require :mimis))

(local repl {:repls {}})

(fn project-has-repl [filetype]
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (and (. repl :repls (.. path filetype))
         (not= (. repl :repls (.. path filetype)) nil))))

(fn get-project-repl [filetype]
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (if (and (. repl :repls (.. path filetype))
             (not= (. repl :repls (.. path filetype)) nil)
             (> (vim.fn.bufexists (. (. repl :repls (.. path filetype)) :buf)) 0))
      (. repl :repls (.. path filetype))
      (let [buf (vim.api.nvim_create_buf true true)
                r {:buf buf}]
        (set (. repl :repls (.. path filetype)) r)
        (. repl :repls (.. path filetype)))))) 

(fn set-project-repl [filetype v]
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (set (. repl :repls (.. path filetype)) v)))

(fn current-ns []
  "("
    (mimis.first 
      (mimis.split (mimis.second (vim.fn.split (vim.fn.getline 1) " ")) ")")))

(fn show-repl [enter filetype]
  (if (project-has-repl filetype)
    (let [r (get-project-repl filetype)]
      (mimis.buff r.opts r.buf)
      (when enter
        (vim.cmd.normal "G"))
      (set-project-repl filetype r))
    (print "No repl started, please start.")))

(fn send [expression filetype]
  (let [r (get-project-repl filetype)
        e (if (= (type expression) "string") expression (expression))]
    (if (and r r.repl r.buf)
      ((. r.repl :send) e)
      (print "Repl not connected"))))

(fn get-command [filetype]
  (case filetype
    :fennel
    (let [root (vim.fn.call "FindRootDirectory" [])]
      (if (mimis.exists? (.. root "/.mimis.repl.fennel"))
        (?. (vim.fn.readfile (.. root "/.mimis.repl.fennel")) 1)
        :fennel))
    :lisp "rlwrap sbcl"
    :sql (let [root (vim.fn.call "FindRootDirectory" [])]
      (if (mimis.exists? (.. root "/.mimis.repl.sql"))
          (?. (vim.fn.readfile (.. root "/.mimis.repl.sql")) 1)
          (.. "psql -h " "localhost" 
              " -d " "database" 
              " -U " "username" 
              " -p " "5432" 
              " -P footer=off -P pager=off -P format=wrapped")))
    :clojure 
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          shadow-cljs (mimis.exists? (.. root "/shadow-cljs.edn"))
          deps-edn  (mimis.exists? (.. root "/deps.edn"))]
      (case [project-clj shadow-cljs deps-edn]
        [true false false] "lein repl"
        [false true false] "npx shadow-cljs clj-repl"
        [false false true] "clojure -A:dev:dev/nrepl"
        _ "bb"))))

(fn visible? [buf]
  (not= -1 (vim.fn.bufwinid buf)))  

(fn ensure-shown [filetype r]
  (when (and r.buf (not (visible? r.buf)))
    (mimis.buff r.opts r.buf)
    (set-project-repl filetype r)))

(fn sender [filetype r job show data]
  (vim.schedule
    (fn []
      (if r.buf
        (when data
          (vim.fn.chansend job (.. data (case filetype :sql "" _ "\n")))
          (set-project-repl filetype r)
          (when show (ensure-shown filetype r)))
        (print "Repl not connected")))))

(fn connect-repl [filetype connection]
  (let [r (get-project-repl filetype)]
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          command (when project-clj (.. "lein repl :connect " connection))
          job (when command (vim.fn.jobstart command {:term true}))]
      (if job 
        (do
          (set vim.bo.filetype filetype)
          {:job job
           :quiet-send (partial sender filetype r job false)
           :send (partial sender filetype r job true)})
        (print "Cannot find a repl type to connect to for this project")))))

(fn start-repl [filetype]
  (let [r (get-project-repl filetype)]
    (let [command (get-command filetype)
          job (vim.fn.jobstart command {:term true})]
      (set vim.bo.filetype filetype)
      {:job job
       :quiet-send (partial sender filetype r job false)
       :send (partial sender filetype r job true)})))

(fn jack-in [opts filetype]
  (let [r (get-project-repl filetype)]
    (set r.opts opts)
    (show-repl true filetype)
    (when (not r.repl) (set r.repl (start-repl filetype)))
    (set-project-repl filetype r)))

(fn connect-in [opts filetype connection-str]
  (let [r (get-project-repl filetype)]
    (set r.opts opts)
    (show-repl true filetype)
    (when (not r.repl) (set r.repl (connect-repl filetype connection-str)))
    (set-project-repl filetype r)))

{: current-ns
 : jack-in
 : get-command
 : connect-in
 : send }
