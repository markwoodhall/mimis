;; Hands the output of a command you ran to the agent, without giving the agent what
;; it took to run it: the command runs here, outside any sandbox, with your credentials.
;; Its stdout is saved under the project, which a sandboxed agent can read, and the
;; chat's prompt gets a line saying where. stderr isn't saved with it, so the file
;; stays valid JSON.
;;
;; :AcpRun runs a command you type, in a terminal, and nothing is sent: you add the
;; question and send it, or take the line out. g! in the chat runs the shell code card
;; under the cursor, one the agent wrote when you'd rather run its command yourself.
;; Under the card the chat asks, as the agent's permission requests do, showing the
;; command as it will run; <CR> on a choice answers. It runs out of sight, the chat
;; saying so, and a comment on the card then says where its output is, or how it failed
;; and what it said on stderr, and goes to the agent straight away, its reply in a
;; thread under the card. An aws logs start-query
;; either way waits for the query and saves its results.
;;
;; A screenshot goes the same way: taken here, where the display is, and saved beside
;; the rest for an agent that can read images. :AcpPath only adds a line naming files
;; that are already there.
;;
;; The files stay in vim.g.acp-output-dir (.acp in the project by default), which
;; ignores itself in git, until you delete them.

(local render (require :modules.acp.render))
(local session (require :modules.acp.session))

;; Lines for the prompt of the next session, when a command finishes with none running.
(local waiting [])

;; Marks the code cards being run, to find each again to comment on once it's done.
(local card-ns (vim.api.nvim_create_namespace "acp-handoff-card"))

;; The cards asking whether to run them, each {:session :block :offset :run}: block is
;; the question's line, offset how many of its attached lines come before the choices.
(local asking [])

(local choices [{:name "Run it"} {:name "Don't run it"}])

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
  (.. "Output of: " shown " — " (saved-to path)))

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
          (vim.notify (.. "acp: " path " is in the prompt, :Acp to ask about it"))))
      (do
        (table.insert waiting line)
        (vim.notify (.. "acp: " path " will be in the prompt of the next :Acp"))))))

(fn comment-on-card [card path text]
  ;; Comments on the card the command came from and sends it, its reply in a thread
  ;; under the card; queued if a turn is running. Whether it could: the card's gone if
  ;; its session ended or its lines were deleted.
  (let [s card.session
        [row _ details] (if (and (session.alive? s) (vim.api.nvim_buf_is_valid s.buf))
                          (vim.api.nvim_buf_get_extmark_by_id s.buf card-ns card.mark {:details true})
                          [])
        at (when (and row (not details.invalid))
             (render.add-comment s (+ row 1) (+ row 1)))]
    (when at
      (vim.api.nvim_buf_set_lines s.buf (- at 1) at false (vim.split text "\n" {:plain true}))
      ((session.comment-action s at))
      (when (not (render.visible? s.buf))
        (vim.notify (.. "acp: sent " path " to the agent")))
      true)))

(fn finished [target path shown]
  (if (<= (vim.fn.getfsize path) 0)
    (do
      (vim.fn.delete path)
      (vim.notify "acp: the command wrote no output, nothing to hand over" vim.log.levels.WARN))
    (deliver target path (reference shown path))))

(fn fenced-tail [text]
  ;; The last 40 lines of text, in a fence no backticks in it can close.
  (let [lines (vim.split text "\n" {:plain true})
        kept (vim.list_slice lines (math.max 1 (- (length lines) 39)))]
    (var fence "```")
    (each [run (string.gmatch text "`+")]
      (when (>= (length run) (length fence))
        (set fence (string.rep "`" (+ (length run) 1)))))
    (.. fence "\n" (if (< (length kept) (length lines)) "…\n" "")
        (table.concat kept "\n") "\n" fence)))

(fn card-report [path code stderr]
  ;; What the agent is told about the command it asked you to run: where its output
  ;; is, and if it failed or printed nothing, what it said on stderr, so it can
  ;; suggest another.
  (let [output? (> (vim.fn.getfsize path) 0)
        said? (and (not= stderr "") (or (not= code 0) (not output?)))]
    (when (not output?) (vim.fn.delete path))
    (.. (if (= code 0) "I ran it" (.. "I ran it and it failed, exit code " code))
        (if output? (.. ", its output is " (saved-to path))
            (= code 0) ", it printed nothing"
            "")
        (if said? (.. ". On stderr:\n\n" (fenced-tail stderr)) "."))))

(fn project-for [target]
  (if (session.alive? target) target.session.cwd (session.project-root)))

(fn terminal [opts cmd path]
  ;; Runs cmd in a terminal as mimis.shell would, in the window or split opts' modifiers
  ;; ask for, saving its stdout to path. The command goes to the shell as it is:
  ;; :terminal would expand % and # in it. The } on a line of its own ends a script
  ;; ending in a heredoc too.
  (if (or opts.smods.vertical opts.smods.horizontal (not= opts.smods.split "")
          (>= opts.smods.tab 0))
    (vim.cmd (.. opts.mods " new"))
    (vim.api.nvim_win_set_buf 0 (vim.api.nvim_create_buf true false)))
  (vim.fn.jobstart (.. "{ " cmd "\n} | tee " (vim.fn.shellescape path)) {:term true})
  (vim.cmd "setlocal norelativenumber nonumber nolist")
  (vim.api.nvim_get_current_buf))

(fn start [opts target name cmd shown extension]
  ;; Runs cmd in a terminal, and hands its output over when it ends. name starts the
  ;; file's name; shown is the command as the agent is told about it; extension is the
  ;; file's, json if not given.
  (let [path (output-file (project-for target) name (or extension "json"))
        buf (terminal opts cmd path)]
    (vim.api.nvim_create_autocmd :TermClose
      {:buffer buf
       :once true
       :desc "Hand the command's output to the ACP session"
       :callback #(do (finished target path shown) nil)})
    buf))

(fn run-in-chat [s name cmd shown extension card]
  ;; Runs cmd out of sight, its stdout saved, while the chat says it's running: unless
  ;; a turn is, which says what it's doing itself. Then hands the output over.
  (let [path (output-file (project-for s) name extension)
        first-line (. (vim.split shown "\n" {:plain true}) 1)
        label (.. "running " (if (> (vim.fn.strchars first-line) 40)
                               (.. (vim.fn.strcharpart first-line 0 40) "…")
                               first-line))
        quiet? (= s.turn.state :idle)]
    (when quiet? (render.activity s label))
    (vim.system (vim.list_extend (vim.split vim.o.shell " " {:trimempty true})
                                 [vim.o.shellcmdflag
                                  (.. "{ " cmd "\n} > " (vim.fn.shellescape path))])
                {:text true}
                (vim.schedule_wrap
                  (fn [result]
                    (when (and quiet? (= s.turn.state :idle) (= (?. s.activity :label) label))
                      (render.activity s nil))
                    (let [report (card-report path result.code (vim.trim (or result.stderr "")))]
                      (when (not (comment-on-card card "the result" report))
                        (if (= 1 (vim.fn.filereadable path))
                          (deliver s path (reference shown path))
                          (vim.notify (.. "acp: the card's gone, so this went nowhere: " report)
                                      vim.log.levels.WARN)))))))))

(local insights-command
  (.. (vim.fn.shellescape (.. (vim.fn.stdpath :config) "/bin/aws-insights")) " "))

(fn shell-kind [cmd]
  ;; The file's name and extension for cmd's output, and what to run for it: an aws
  ;; logs start-query goes through aws-insights, to save the query's results, not its
  ;; id; other aws output is JSON unless it asks for another format.
  (let [aws-args (string.match cmd "^%s*aws(%s.*)$")
        program (vim.fn.fnamemodify (or (string.match cmd "%S+") "output") ":t")]
    (if (and aws-args (string.find aws-args "%slogs%s") (string.find aws-args "%sstart%-query%f[%s%z]"))
      (values "insights" "json" (.. insights-command aws-args))
      aws-args
      (values "aws" (if (string.find aws-args "%-%-output[%s=]+[^j%s]") "txt" "json") cmd)
      (values (pick-values 1 (string.gsub program "[^%w_.-]" "-")) "txt" cmd))))

(fn run-shell [opts cmd]
  (let [(name extension runs) (shell-kind cmd)]
    (start opts (session.here) name runs cmd extension)))

(fn card-command [lines]
  ;; A card's lines as one command: a \ at a line's end joins the next to it, and a
  ;; leading $ prompt goes.
  (let [joined (-> (table.concat lines "\n")
                   (string.gsub "%s*\\\n%s*" " ")
                   (string.gsub "^%$%s+" "")
                   (string.gsub "\n%$%s+" "\n"))]
    (vim.trim joined)))

(fn run-card [s row]
  ;; Asks under the shell code card at row (1-based) in s's chat whether to run it,
  ;; showing what will run, and puts the cursor on yes.
  (let [block (render.fence-at s.buf row)
        lang (string.lower (or (?. block :lang) ""))
        shell? (or (= lang "") (= :sh (. render.filetype-aliases lang)) (= lang :sh))
        cmd (when block
              (card-command (vim.api.nvim_buf_get_lines s.buf (- block.from 1) block.to false)))]
    (if (not block)
      (vim.notify "acp: no code card here" vim.log.levels.WARN)
      (not shell?)
      (vim.notify (.. "acp: this card is " lang ", not a shell command") vim.log.levels.WARN)
      (= cmd "")
      (vim.notify "acp: this card is empty" vim.log.levels.WARN)
      (let [(name extension runs) (shell-kind cmd)
            question {:type :line :line "> permission: run this here, outside the sandbox — awaiting choice"}]
        (if (not (render.add-line-under s question (- block.from 1)))
          (vim.notify "acp: nowhere to ask about this card" vim.log.levels.WARN)
          (let [(lines offset) (render.permission-lines s {} runs :execute choices)
                mark (vim.api.nvim_buf_set_extmark s.buf card-ns (- block.from 1) 0
                                                   {:invalidate true :undo_restore false})]
            (render.attach-lines s question lines)
            (table.insert asking
                          {:session s :block question : offset
                           :run #(run-in-chat s name runs cmd extension {:session s : mark})
                           :drop #(vim.api.nvim_buf_del_extmark s.buf card-ns mark)})
            (vim.api.nvim_win_set_cursor 0 [(+ (render.line-row s question) offset 1) 0])))))))

(fn choice-at [s row]
  ;; The question and the index of the choice (1 runs it) on chat row (1-based), if any.
  (accumulate [found nil i q (ipairs asking) &until found]
    (let [index (when (= q.session s) (render.attached-index s q.block row))
          choice (when index (- index q.offset))]
      (when (and choice (. choices choice))
        {: i : choice}))))

(fn choose-at [s row]
  ;; Answers the question on row: takes it away, then runs the card's command, or
  ;; doesn't.
  (let [hit (choice-at s row)]
    (when hit
      (let [q (table.remove asking hit.i)]
        (render.remove-line s q.block)
        (if (= hit.choice 1) (q.run) (q.drop))))))

(fn link [paths]
  ;; Points the agent at files or directories you name, without copying anything: one
  ;; line per path, absolute, so it reads the same from any directory. A path outside
  ;; the project may be out of a sandboxed agent's reach, so that gets a warning.
  (let [target (session.here)
        root (vim.fn.fnamemodify (project-for target) ":p")]
    (each [_ p (ipairs paths)]
      (let [expanded (vim.fn.expand p)
            full (vim.fn.fnamemodify expanded ":p")]
        (if (or (= expanded "")
                (and (= 0 (vim.fn.filereadable full)) (= 0 (vim.fn.isdirectory full))))
          (vim.notify (if (= expanded "") "acp: this buffer has no file" (.. "acp: no such file: " p))
                      vim.log.levels.WARN)
          (do
            (when (not (vim.startswith full root))
              (vim.notify (.. "acp: " full " is outside the project, a sandboxed agent may not be able to read it")
                          vim.log.levels.WARN))
            (deliver target full (.. "See " full))))))))

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
  ;; seconds is how long to wait before selecting, vim.g.acp-screenshot-seconds (10) if
  ;; not given: once the crosshair is up the window manager can't change workspace, and
  ;; what you want to share is usually on another one, or in another thread to go to
  ;; first. It says nothing on the way: with 'cmdheight' 0 a message is a prompt to
  ;; dismiss, and the crosshair is cue enough.
  (let [target (session.here)
        seconds (or seconds vim.g.acp-screenshot-seconds 10)
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

{: run-shell
 : run-card
 : choice-at
 : choose-at
 : link
 : screenshot
 : flush}
