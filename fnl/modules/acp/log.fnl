;; Markdown session log: one file per session, one append per completed turn.

(fn log-dir []
  (vim.fn.expand (or vim.g.acp-log-dir "~/agent-log")))

(fn git-hash [cwd]
  (let [out (vim.fn.systemlist ["git" "-C" cwd "rev-parse" "--short" "HEAD"])]
    (if (= vim.v.shell_error 0) (. out 1) "none")))

(fn init [s]
  (set s.log {:path nil
              :git (git-hash s.session.cwd)
              :written-turns 0}))

(fn slugify [text]
  (let [words (icollect [w (string.gmatch (string.lower text) "%w+")] w)
        firsts (fcollect [i 1 (math.min 6 (length words))] (. words i))]
    (if (= (length firsts) 0)
      "session"
      (table.concat firsts "-"))))

(fn unique-path [base]
  (var path (.. base ".md"))
  (var n 2)
  (while (= 1 (vim.fn.filereadable path))
    (set path (.. base "-" n ".md"))
    (set n (+ n 1)))
  path)

(fn header [s]
  (let [lines ["---"
               (.. "date: " (os.date "%Y-%m-%dT%H:%M" s.session.started))
               (.. "project: " s.session.project)
               (.. "cwd: " s.session.cwd)
               (.. "agent: " (table.concat s.agent.cmd " "))]]
    (each [_ o (ipairs (or s.config []))]
      (table.insert lines (.. o.id ": " o.display)))
    (vim.list_extend lines [(.. "session: " (or s.session.id ""))
                            (.. "git: " s.log.git)
                            "---"
                            ""])))

(fn create [s first-prompt]
  (let [dir (log-dir)
        base (.. dir "/"
                 (os.date "%Y-%m-%d-%H%M" s.session.started)
                 "-" s.session.project
                 "-" (slugify first-prompt))]
    (vim.fn.mkdir dir :p)
    (set s.log.path (unique-path base))
    (vim.fn.writefile (header s) s.log.path)))

(fn turn-lines [turn]
  ;; Mirrors how render lays out the chat buffer, so the log reads the same.
  (let [lines [(.. "## You — " turn.time)]]
    (vim.list_extend lines (vim.split turn.prompt "\n" {:plain true}))
    (vim.list_extend lines ["" "## Agent" ""])
    (each [_ b (ipairs turn.blocks)]
      (if (= b.type :text)
        (let [parts (vim.split b.text "\n" {:plain true})
              n (length lines)]
          (tset lines n (.. (. lines n) (table.remove parts 1)))
          (vim.list_extend lines parts))
        (let [n (length lines)
              previous (. lines (- n 1))]
          (if (not= (. lines n) "")
            (vim.list_extend lines ["" b.line ""])
            (or (= previous "") (previous:match "^[>#]"))
            (do
              (tset lines n b.line)
              (table.insert lines ""))
            (do
              (tset lines n "")
              (vim.list_extend lines [b.line ""]))))))
    (while (and (> (length lines) 0) (= (vim.trim (. lines (length lines))) ""))
      (table.remove lines))
    (table.insert lines "")
    lines))

(fn append-turn [s turn]
  (when (not s.log.path)
    (create s turn.prompt))
  (vim.fn.writefile (turn-lines turn) s.log.path "a")
  (set s.log.written-turns (+ s.log.written-turns 1)))

(fn append-note [s line]
  ;; Before the first turn there's no file yet; the header will carry the current state.
  (when s.log.path
    (vim.fn.writefile [line ""] s.log.path "a")))

{: init
 : append-turn
 : append-note
 : log-dir
 : slugify
 : turn-lines}
