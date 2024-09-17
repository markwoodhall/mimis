(local mimis (require :mimis))
(local nvim (require :nvim))

(local 
  repl 
  {:repls {}
   :window-options 
   {:relative :editor
    :border :single
    :anchor :NE
    :row 1
    :col (-> (vim.api.nvim_list_uis)
             (. 1)
             (. :width)) 
    :width (math.floor (+ (/ (-> (vim.api.nvim_list_uis)
                                 (. 1)
                                 (. :width)) 3) 0.5))
    :height (math.floor (+ (/ (-> (vim.api.nvim_list_uis)
                                  (. 1)
                                  (. :height)) 3) 0.5))}})

(fn get-project-repl []
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (or (. repl :repls path)
        (let [buf (vim.api.nvim_create_buf true true)
              r {:last-ns nil
                 :buf buf
                 :win (vim.api.nvim_open_win 
                        buf
                        true 
                        repl.window-options)}]
          (set (. repl :repls path) r)
          (. repl :repls path))))) 

(fn set-project-repl [v]
  (let [path (vim.fn.call "FindRootDirectory" [])]
    (set (. repl :repls path) v)))

(fn current-ns []
  "("
  (mimis.first 
    (mimis.split (mimis.second (vim.fn.split (vim.fn.getline 1) " ")) ")")))

(fn in-ns [start-ns]
  (let [r (get-project-repl)]
    (when r
      (let [ns (or start-ns (current-ns))]
        (when (and ns (not= r.last-ns ns))
          (r.repl.send (.. "(in-ns '" ns ")"))
          (set r.last-ns ns)
          (set-project-repl r))))))

(fn hide-repl []
  (let [r (get-project-repl)]
    (if (and r r.win)
      (pcall vim.api.nvim_win_hide (unpack [r.win])))))

(fn show-repl [enter]
  (let [r (get-project-repl)]
    (set r.win 
         (vim.api.nvim_open_win 
           r.buf 
           enter
           repl.window-options))))

(fn kill-repl []
  (let [r (get-project-repl)]
    (when r.repl
      (do (hide-repl) (show-repl true)))
    (vim.cmd ":bd!")
    (set r.repl nil)
    (set r.win nil)
    (set r.buf nil)
    (set-project-repl r)))

(fn send [expression ns]
  (let [r (get-project-repl)
        e (if (= (type expression) "string") expression (expression))]
    (when (and (not= :none ns)) 
      (if (or (not ns)
              (= :current ns))
        (in-ns)
        (in-ns ns)))
    ((. r.repl :send) e)))

(fn get-command [filetype]
  (match filetype
    :fennel "fennel"
    :clojure 
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          shadow-cljs (mimis.exists? (.. root "/shadow-cljs.edn"))
          deps-edn  (mimis.exists? (.. root "/deps.edn"))]
      (match [project-clj shadow-cljs deps-edn]
        [true false false] "lein repl"
        [false true false] "npx shadow-cljs clj-repl"
        [false false true] "clojure -A:dev:dev/nrepl"
        _ "lein repl"))))

(fn connect-repl [filetype connection]
  (let [r (get-project-repl)]
    (let [root (vim.fn.call "FindRootDirectory" [])
          project-clj (mimis.exists? (.. root "/project.clj"))
          command (when project-clj (.. "lein repl :connect " connection))
          job (when command (vim.fn.termopen command))]
      (if job 
        (do
          (vim.cmd "setlocal norelativenumber")
          (vim.cmd "setlocal nonumber")
          (set nvim.bo.filetype filetype)
          (set nvim.bo.syntax filetype)
          {:job job
           :send (fn [data]
                   (hide-repl)
                   (set r.win 
                        (vim.api.nvim_open_win 
                          r.buf 
                          false
                          repl.window-options))
                   (vim.fn.chansend job (.. data "\n")))})
        (print "Cannot find a repl to connect to for this project")))))

(fn start-repl [filetype]
  (let [r (get-project-repl)]
    (let [command (get-command filetype)
          job (vim.fn.termopen command)]
      (vim.cmd "setlocal norelativenumber")
      (vim.cmd "setlocal nonumber")
      (set nvim.bo.filetype filetype)
      (set nvim.bo.syntax filetype)
      {:job job
       :send (fn [data]
               (hide-repl)
               (set r.win 
                    (vim.api.nvim_open_win 
                      r.buf 
                      false
                      repl.window-options))
               (when data
                 (vim.fn.chansend job (.. data "\n"))))})))

(fn jack-in [filetype]
  (let [r (get-project-repl)]
    (if (and r r.repl)
      (do (hide-repl) (show-repl true))
      (do 
        (set r.repl (start-repl filetype))
        (set-project-repl r)))))

(fn connect-in [filetype connection-str]
  (let [r (get-project-repl)]
    (if (and r r.repl)
      (do (hide-repl) (show-repl true))
      (do 
        (set r.repl (connect-repl filetype connection-str))
        (set-project-repl r)))))

{: current-ns
 : in-ns
 : hide-repl
 : show-repl
 : kill-repl
 : jack-in
 : connect-in
 : send }
