(local mimis (require :mimis))

(fn verbatim [results indent lang]
  (case lang
    "sql" (let [t (mimis.split results "\n")
                t (icollect [_ v  (ipairs t)]
                    (when (not (= "Timing is off." v))
                      (.. (mimis.pad-string " " indent) 
                          (if (not= v "") 
                              (.. "|" v 
                                  (if (or (string.find v " $")
                                          (string.find v "-$"))
                                      "|"
                                      " |")) v))))] 
            (table.insert t 1 (.. (mimis.pad-string " " indent) "#+RESULTS:"))
            t)
    _ (let [t (mimis.split results "\n")
            t (icollect [_ v  (ipairs t)]
                (.. (mimis.pad-string " " indent) v))] 
            (table.insert t 1 (.. (mimis.pad-string " " indent) "#+RESULTS:"))
            t)))

(fn presenter [p-type]
  (case p-type
    :verbatim verbatim
    _ verbatim))

(fn command [lang]
  (case lang
    "bash" (fn [env code]
             (let [code (string.gsub (mimis.join code " ") "^%s*" "")
                   fname (.. (vim.fn.tempname) ".sh")]
               (with-open [fout (io.open fname :w)]
                    (fout:write code))
               (vim.fn.system 
                 (.. env 
                     " bash " fname))))
    "sql" (fn [env code]
                (let [fname (.. (vim.fn.tempname) ".sql")]
                  (with-open [fout (io.open fname :w)]
                    (fout:write (.. "\\timing off\n" (mimis.join code "\n"))))
                  (vim.fn.system 
                    (.. env 
                        " psql -P footer=off -q -f " fname))))
    "clojure" (fn [env code]
                (let [fname (.. (vim.fn.tempname) ".clj")]
                  (with-open [fout (io.open fname :w)]
                    (fout:write (mimis.join code "\n")))
                  (vim.fn.system 
                    (.. env 
                        " bb --file " fname))))
    "fennel" (fn [env code]
               (let [fname (.. (vim.fn.tempname) ".fnl")]
                 (with-open [fout (io.open fname :w)]
                   (fout:write (mimis.join code "\n")))
                 (vim.fn.system 
                   (.. env 
                       " fennel " fname))))
    "kotlin" (fn [env code]
               (let [fname (.. (vim.fn.tempname) ".kts")]
                 (with-open [fout (io.open fname :w)]
                   (fout:write (mimis.join code "\n")))
                 (vim.fn.system 
                   (.. env 
                       " kotlinc -script " fname))))))

(fn parse-sql-header [_ header]
  (if header
    (let [parts (mimis.split header ":")
          kvs (icollect [_ v (ipairs parts)]
                (let [options (mimis.split v " ")]
                  (case (mimis.first options)
                    "engine" ""
                    "dbuser" (.. "PGUSER=" (mimis.last options))
                    "dbpassword" (.. "PGPASSWORD=" (mimis.last options))
                    "dbhost" (.. "PGHOST=" (mimis.last options))
                    "dbport" (.. "PGPORT=" (mimis.last options))
                    "database" (.. "PGDATABASE=" (mimis.last options)))))]
      (mimis.->environment-variables
        (mimis.join kvs "\n")))))

(fn header-parser [lang _header]
  (case lang
    "sql" parse-sql-header
    _ (fn [_ _] "")))

(fn clear-code-block [from-line]
  (let [pos (vim.fn.winsaveview)
        [line1 _] (vim.fn.searchpos "\\c#+RESULTS" "c")
        [line2 _] (vim.fn.searchpos "\\c^$" "c")
        [next-src-line _] (vim.fn.searchpos "\\c#+begin_src" "c")
        line2 (if (< line2 line1)
                  (vim.fn.line "$")
                  line2)]
    (when (and (> line1 0)
               (> line1 from-line)
               (> next-src-line line1))
      (vim.cmd (.. line1 "," line2 "d")))
    (vim.fn.winrestview pos)))

(fn get-code-block []
  (let [curr-lin (vim.fn.line ".")
        [line1 pos] (vim.fn.searchpos "\\c#+begin_src" "bc")
        [line2 _] (vim.fn.searchpos "\\c#+end_src$" "c")
        code (vim.fn.getline (+ line1 1) (- line2 1))
        line (vim.fn.getline line1)
        lang (mimis.first (mimis.split (mimis.last (mimis.split line "\\c#+begin_src ")) " "))
        [prop-line1 _] (vim.fn.searchpos (.. "\\c#+property: header-args:" lang " ") "bc")
        prop-line (vim.fn.getline prop-line1)
        cmd (command lang)]
    (when (and cmd
               (>= curr-lin line1)
               (>= line2 curr-lin))
      (let [headers (mimis.split line (.. "\\c#+begin_src " lang " "))
            prop-headers (mimis.split prop-line (.. "\\c#+property: header-args:" lang " "))
            header (mimis.last headers)
            prop-header (mimis.last prop-headers)
            header (if (> (length headers) 1) header prop-header)
            header-parser-fn (header-parser lang header)
            env (header-parser-fn lang header)]
        {:pos pos
         :lang lang
         :cmd cmd
         :code code
         :start-line line1
         :end-line line2
         :env env}))))

(fn parse-header [header]
  (if header
    (let [parts (mimis.split header ":")
          kvs (accumulate [h {:tangle nil :shebang nil :mkdirp nil} _ v (ipairs parts)]
                (let [options (mimis.split v " ")]
                  (case (mimis.first options)
                    "shebang" (set h.shebang (mimis.last options))
                    "tangle" (set h.tangle (mimis.last options))
                    "mkdirp" (set h.mkdirp (mimis.last options))
                    "SHEBANG" (set h.shebang (mimis.last options))
                    "TANGLE" (set h.tangle (mimis.last options))
                    "MKDIRP" (set h.mkdirp (mimis.last options)))
                  h))]
      kvs)))

(fn org-blocks []
  (let [lines (vim.api.nvim_buf_get_lines 0 0 -1 false)
        blocks []]
    (var current nil)
    (each [_ line (ipairs lines)]
      (let [l (line:lower)]
        (if (l:match "^%s*#%+begin_src")
            (set current {:header line :source []})

            (and current (l:match "^%s*#%+end_src"))
            (do (table.insert blocks current)
                (set current nil))

            current
            (table.insert current.source line))))
    blocks))

(fn tangle-blocks []
  (let [ seen {}]

    (each [_ block (ipairs (org-blocks))]
      (let [header block.header
            source block.source
            parsed-header (parse-header header)]
        (when (or (> (mimis.count-matches header "begin_src") 0)
                  (> (mimis.count-matches header "BEGIN_SRC") 0))
          (let [file (. parsed-header :tangle)
                append? (. seen file)
                _ (set (. seen file ) true)
                mkdirp (. parsed-header :mkdirp)
                shebang (. parsed-header :shebang)
                dir (vim.fn.expand (vim.fn.fnamemodify (vim.fn.expand file) ":h"))]
            (when (= mkdirp "yes")
              (vim.fn.mkdir dir "p"))
            (when file
              (print (.. "Tangling code block to file " file))
              (when shebang 
                (if (mimis.exists? (vim.fn.expand file))
                  (vim.fn.writefile [shebang] (vim.fn.expand file) (if append? "a" ""))
                  (vim.fn.writefile [shebang] (vim.fn.expand file))))
              (if (mimis.exists? (vim.fn.expand file))
                (vim.fn.writefile source (vim.fn.expand file) (if append? "a" ""))
                (vim.fn.writefile source (vim.fn.expand file))))))))))

(fn eval-code-block []
  (let [winpos (vim.fn.winsaveview)
        code-block (get-code-block)
        _ (vim.fn.winrestview winpos)]
    (when code-block
      (let [env (. code-block :env)
            cmd (. code-block :cmd)
            code (. code-block :code)
            pos (. code-block :pos)
            start-line (. code-block :start-line)
            end-line (. code-block :end-line)
            presenter (presenter :verbatim)
            output (presenter (cmd env code) (- pos 1) (. code-block :lang))]
        (clear-code-block start-line)
        (vim.fn.append end-line output)))))

{: eval-code-block
 : tangle-blocks }
