(local mimis (require :mimis))
(local notes-path (fn [] (or vim.g.mimis-notes-path (vim.fn.expand "~/mimis-notes"))))
(local pandoc-opts (fn [] (or vim.g.mimis-notes-pandoc-opts "")))

(fn the-date []
  (os.date "%d-%m-%Y"))

(fn note-id []
  (string.gsub (the-date) "/" "-"))

(fn note-dir [notes-path workspace]
  (.. notes-path "/" workspace))

(fn note-file [notes-path id workspace ftype]
  (.. (note-dir notes-path workspace) "/" id ftype))

(fn completion [_ c]
  (let [c-parts (mimis.split c " ")]
    (if (< (mimis.count-matches c "%s") 2)
      (let [dirs (mimis.glob (.. (notes-path) "/" (or (?. c-parts 2) "") "*"))]
        (icollect [_ v (ipairs dirs)]
          (let [parts (mimis.split v "/")]
            (. parts (length parts)))))
      (let [notes (mimis.glob (.. (notes-path) "/" (. c-parts 2) "/" (or (?. c-parts 3) "") "*.org"))]
        (icollect [_ v (ipairs notes)]
          (let [parts (mimis.split v "/")]
            (string.gsub (. parts (length parts)) ".org" "")))))))

(fn export [file]
  (let [out-pdf (.. (string.gsub file ".org$" ".pdf"))
        out-md (.. (string.gsub file ".org$" ".md"))
        out-html ( .. (string.gsub file ".org$" ".html"))
        toc (> (mimis.count-matches (mimis.join (vim.fn.readfile file) "") "toc:t") 0)]
    (vim.cmd (.. "!pandoc --pdf-engine=xelatex -o " out-pdf " " file))
    (vim.cmd (.. "!pandoc -o " out-md " " file))
    (if toc
      (vim.cmd (.. "!pandoc --standalone --toc " (pandoc-opts) " -o " out-html " " file))
      (vim.cmd (.. "!pandoc --standalone " (pandoc-opts) " -o " out-html " " file)))))

(fn note-window [note-file]
  (mimis.bottom-pane "org" note-file true false)
  (vim.fn.call "setpos" ["." (vim.fn.call "getpos" ["$"])]))

(fn start-note [workspace note-file include-date]
  (with-open [fout (io.open note-file :w)]
    (fout:write (.. "#+TITLE: " (string.upper workspace) " NOTES"))
    (fout:write "\n")
    (fout:write (.. "#+AUTHOR: " (vim.fn.expand "$USER")))
    (fout:write "\n")
    (fout:write (.. "#+DATE: " (the-date)))
    (fout:write "\n")
    (fout:write (.. "#+OPTIONS: tags:nil:"))
    (fout:write "\n")
    (fout:write "\n\n")
    (fout:write (.. "[[../" workspace "/index.html][Index]] [[../" workspace "/index.org][~Org~]]"))
    (when include-date (fout:write "\n\n"))
    (when include-date (fout:write (.. "* " (the-date))))
    (fout:write "\n\n")))

(fn workspace-index [workspace id]
  (let [link (.. id ".html")
        note-file (note-file (notes-path) "index" workspace ".org")]
    (if (not (mimis.exists? note-file))
      (do 
        (os.execute (.. "mkdir " (note-dir (notes-path) workspace)))
        (start-note workspace note-file false)
        (with-open [fout (io.open note-file :a)]
          (fout:write (.. "-  [[../" workspace "/" link "][" id "]] [[../" workspace "/" id ".org][~Org~]]"))
          (fout:write "\n"))
        (export note-file))
      (do 
        (with-open [fout (io.open note-file :a)]
          (fout:write "\n")
          (fout:write (.. "-  [[../" workspace "/" link "][" id "]] [[../" workspace "/" id ".org][~Org~]]"))
          (fout:write "\n"))
        (export note-file)))))

(fn new-note [id workspace]
  (let [note-file (note-file (notes-path) id workspace ".org")]
    (if (not (mimis.exists? note-file))
      (do 
        (os.execute (.. "mkdir " (note-dir (notes-path) workspace)))
        (start-note workspace note-file true)
        (workspace-index workspace id))
      (with-open [fout (io.open note-file :a)]
        (fout:write "\n")
        (fout:write (.. "* " (os.date "%X")))
        (fout:write "\n\n\n")))
    (note-window note-file)))

(fn review-note [id workspace]
  (let [note-file (note-file (notes-path) id workspace ".org")]
    (when (not (mimis.exists? note-file))
      (os.execute (.. "mkdir " (note-dir (notes-path) workspace)))
      (start-note workspace note-file true))
    (note-window note-file)))

(fn insert-note-link [id workspace]
  (let [note-file (note-file (notes-path) id workspace ".org")]
    (when (mimis.exists? note-file)
      (vim.cmd (.. "normal! i [[../" workspace "/" id ".org.html][" workspace "/" id "]]")))))

(vim.api.nvim_create_user_command
  "NewNote"
  (fn [opts]
    (let [workspace (?. (?. opts :fargs) 1)
          id (?. (?. opts :fargs) 2)
          workspace (if (= "" workspace)
                      "default"
                      workspace)
          n-id (if id id (note-id))]
      (new-note n-id workspace)))
  {:bang false :desc "Create a new note" :nargs "*"
   :complete completion})

(vim.api.nvim_create_user_command
  "ReviewNote"
  (fn [opts]
    (let [workspace (?. (?. opts :fargs) 1)
          id (?. (?. opts :fargs) 2)
          workspace (if (= "" workspace)
                      "default"
                      workspace)
          n-id (if id id (note-id))]
      (review-note n-id workspace)))
  {:bang false :desc "Review Note" :nargs "*"
   :complete completion})

(vim.api.nvim_create_user_command
  "ViewNotePdf"
  (fn [opts]
    (let [workspace (?. (?. opts :fargs) 1)
          id (?. (?. opts :fargs) 2)
          workspace (if (= "" workspace)
                      "default"
                      workspace)
          n-id (if id id (note-id))]
      (vim.cmd (.. "silent !xdg-open " (notes-path) "/" workspace "/" n-id ".pdf"))))
  {:bang false :desc "View a Note" :nargs "*"
   :complete completion})

(vim.api.nvim_create_user_command
  "ViewNoteHtml"
  (fn [opts]
    (let [workspace (?. (?. opts :fargs) 1)
          id (?. (?. opts :fargs) 2)
          workspace (if (= "" workspace)
                      "default"
                      workspace)
          n-id (if id id (note-id))]
      (vim.cmd (.. "silent !xdg-open " (notes-path) "/" workspace "/" n-id ".html"))))
  {:bang false :desc "View a Note" :nargs "*"
   :complete completion})

(vim.api.nvim_create_user_command
  "InsertNoteLink"
  (fn [opts]
    (let [workspace (?. (?. opts :fargs) 1)
          id (?. (?. opts :fargs) 2)
          workspace (if (= "" workspace)
                      "default"
                      workspace)
          n-id (if id id (note-id))]
      (insert-note-link n-id workspace)))
  {:bang false :desc "Insert Note Link" :nargs "*"
   :complete completion})

(vim.api.nvim_create_user_command
  "SwitchNotesPath"
  (fn [opts]
    (let [path (?. (?. opts :fargs) 1)]
      (set vim.g.mimis-notes-path path)
      (vim.api.nvim_create_autocmd 
        "BufWritePost" 
        {:pattern (.. (notes-path) "/**/*.org") 
         :callback (partial 
                     vim.schedule 
                     (fn []
                       (let [file (vim.fn.expand "%:p")]
                         (export file))))})))
  {:bang false :desc "Change notes path" :nargs "*"
   :complete (fn [] (vim.fn.glob "*"))})

(vim.api.nvim_create_autocmd 
  "BufWritePost" 
  {:pattern (.. (notes-path) "/**/*.org") 
   :callback (partial 
               vim.schedule 
               (fn []
                 (let [file (vim.fn.expand "%:p")]
                   (export file))))})
