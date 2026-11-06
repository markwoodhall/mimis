;; Hands the output of a command you ran to the agent, without giving the agent what
;; it took to run it: the command runs here, outside any sandbox, with your credentials.
;; Its stdout is saved under the project, which a sandboxed agent can read, and the
;; chat's prompt gets a line saying where. Nothing is sent: you add the question and send
;; it, or take the line out. stderr only goes to the terminal, so a failed command
;; leaves no file and the one it does leave stays valid JSON.
;;
;; A screenshot goes the same way: taken here, where the display is, and saved beside
;; the rest for an agent that can read images.
;;
;; The files stay in vim.g.acp-output-dir (.acp in the project by default), which
;; ignores itself in git, until you delete them.

(local mimis (require :mimis))
(local render (require :modules.acp.render))
(local session (require :modules.acp.session))

;; Lines for the prompt of the next session, when a command finishes with none running.
(local waiting [])

(fn output-file [root name extension]
  (let [dir (vim.fn.expand (or vim.g.acp-output-dir (.. root "/.acp")))
        ignore (.. dir "/.gitignore")]
    (vim.fn.mkdir dir "p")
    (when (= 0 (vim.fn.filereadable ignore))
      (vim.fn.writefile ["*"] ignore))
    (.. dir "/" name "-" (os.date "%Y%m%d-%H%M%S") "." extension)))

(fn saved-to [path]
  (.. "saved to " path " (" (math.ceil (/ (vim.fn.getfsize path) 1024)) " KB)"))

(fn reference [shown path]
  ;; :terminal unescaped \% for the shell; the agent should read what the shell ran.
  (.. "Output of: " (pick-values 1 (string.gsub shown "\\%%" "%%"))
      " — " (saved-to path)))

(fn receiver [target]
  ;; The session the command was run from, else whichever is current now.
  (if (session.alive? target)
    target
    (let [s (session.current)]
      (when (session.alive? s) s))))

(fn deliver [target path line]
  (let [s (receiver target)]
    (if s
      (do
        (render.add-to-prompt s line)
        (when (not (render.visible? s.buf))
          (vim.notify (.. "acp: output is in the prompt, :Acp to ask about it"))))
      (do
        (table.insert waiting line)
        (vim.notify (.. "acp: output saved to " path
                        ", it will be in the prompt of the next :Acp"))))))

(fn finished [target path shown]
  (if (<= (vim.fn.getfsize path) 0)
    (do
      (vim.fn.delete path)
      (vim.notify "acp: the command wrote no output, nothing to hand over" vim.log.levels.WARN))
    (deliver target path (reference shown path))))

(fn project-for [target]
  (if (session.alive? target) target.session.cwd (session.project-root)))

(fn run [opts name cmd shown]
  ;; Runs cmd in a terminal as mimis.shell does, and hands its output over when it ends.
  ;; name starts the file's name; shown is the command as the agent is told about it.
  (let [target (session.here)
        path (output-file (project-for target) name "json")
        buf (mimis.shell opts (.. "{ " cmd " ; } | tee " (vim.fn.shellescape path 1)))]
    (vim.api.nvim_create_autocmd :TermClose
      {:buffer buf
       :once true
       :desc "Hand the command's output to the ACP session"
       :callback #(do (finished target path shown) nil)})
    buf))

(fn screenshot-argv [source path seconds]
  ;; X11 only, for now. import takes a dragged region or a clicked window. The wait is
  ;; the process's own, as a timer here would stall on any hit-enter prompt.
  (if (= source :clipboard)
    ["sh" "-c" "exec xclip -selection clipboard -t image/png -o > \"$0\"" path]
    ["sh" "-c" "sleep \"$1\" && exec import \"$0\"" path (tostring seconds)]))

(fn screenshot-taken [target path result]
  (if (and (= result.code 0) (> (vim.fn.getfsize path) 0))
    (deliver target path (.. "Screenshot " (saved-to path)))
    (do
      (vim.fn.delete path)
      (let [reason (vim.trim (or result.stderr ""))]
        (vim.notify (.. "acp: no screenshot taken" (if (= reason "") "" (.. ": " reason)))
                    vim.log.levels.WARN)))))

(fn screenshot [source seconds]
  ;; source is :clipboard for the image you copied, else you select one on the screen.
  ;; seconds is how long to wait before selecting, vim.g.acp-screenshot-seconds (3) if
  ;; not given: once the crosshair is up the window manager can't change workspace, and
  ;; what you want to share is usually on another one. It says nothing on the way: with
  ;; 'cmdheight' 0 a message is a prompt to dismiss, and the crosshair is cue enough.
  (let [target (session.here)
        seconds (or seconds vim.g.acp-screenshot-seconds 3)
        path (output-file (project-for target) "screenshot" "png")
        (ok problem) (pcall vim.system (screenshot-argv source path seconds) {}
                            (vim.schedule_wrap #(screenshot-taken target path $1)))]
    (when (not ok)
      (vim.notify (.. "acp: could not take a screenshot: " (tostring problem))
                  vim.log.levels.WARN))))

(fn flush [s]
  ;; A new session takes the output that was waiting for one.
  (each [_ line (ipairs waiting)]
    (render.add-to-prompt s line))
  (while (> (length waiting) 0)
    (table.remove waiting)))

{: run
 : screenshot
 : flush}
