;; Chat Chat buffer. Sees session state, never JSON-RPC.
;;
;; The buffer is a transcript followed by an input area:
;;
;;   ...transcript...
;;   <blank>        <- input-mark; the transcript is every row above it
;;   ## You         <- the input heading
;;   <your prompt>  <- everything below the heading is the prompt
;;
;; Agent output is always written at the end of the transcript, so you can type
;; the next prompt while a reply streams in.

(local ns (vim.api.nvim_create_namespace "acp"))

(fn markdown [buf]
  ;; The bundled markdown ftplugin starts treesitter, which leaves ```diff blocks
  ;; uncoloured without a diff parser; vim syntax colours them via
  ;; markdown_fenced_languages.
  (tset (. vim.bo buf) :filetype :markdown)
  (pcall vim.treesitter.stop buf)
  (tset (. vim.bo buf) :syntax :markdown)
  ;; The tool, permission, elicitation, egress, stop and acp rows carry agent-supplied titles. Left to
  ;; markdown, a stray backtick or fence in a title opens syntax that colours every
  ;; line below it, so keep those rows (and the folded >> thinking) out of markdown.
  (vim.api.nvim_buf_call buf
    (fn []
      (vim.cmd (.. "syntax region AcpUiLine matchgroup=AcpUiPrefix "
                   "start=/^>\\%(>\\| \\%(tool\\|permission\\|elicitation\\|egress\\|stop\\|acp\\):\\)/ "
                   "end=/$/ contains=NONE")))))

(fn chat-name [s]
  ;; A delegated session shares its project with its parent, so it needs its label too.
  (.. "acp://chat/" s.session.project (if s.label (.. "/" s.label) "")))

(local chats {})
;; Shades worked out for each chat buffer in its current redraw.
(local drawing {})

(fn held? [s]
  ;; While you type in the chat, agent writes wait: anything holding a row across the
  ;; edit (insert-mode completion above all) would land on the wrong line. A pause
  ;; with no completion menu open lets them through.
  (let [mode (. (vim.api.nvim_get_mode) :mode)]
    (and (= (vim.api.nvim_get_current_buf) s.buf)
         (or (vim.startswith mode "i") (vim.startswith mode "R"))
         (not (and s.typing-paused (= 0 (vim.fn.pumvisible)))))))

(fn flush [s]
  ;; Writes queued while you typed, in the order they came.
  (let [queued (or s.held [])]
    (set s.held [])
    (when (vim.api.nvim_buf_is_loaded s.buf)
      (each [_ f (ipairs queued)]
        (f)))))

(fn later [s f]
  ;; Runs an agent write now, or once you stop typing.
  (if (held? s)
    (table.insert s.held f)
    (do
      (when (> (length s.held) 0)
        (flush s))
      (f))))

(fn watch-typing [s buf]
  (let [group (vim.api.nvim_create_augroup (.. "acp-typing-" buf) {:clear true})
        on (fn [events callback]
             (vim.api.nvim_create_autocmd events {: group :buffer buf : callback}))]
    (on [:InsertEnter :InsertCharPre] #(set s.typing-paused false))
    ;; <C-c> leaves insert mode without InsertLeave; CursorHold catches that.
    (on :InsertLeave #(do (set s.typing-paused false) (vim.schedule #(flush s))))
    (on :CursorHold #(flush s))
    (on :CursorHoldI #(when (= 0 (vim.fn.pumvisible))
                        (set s.typing-paused true)
                        (flush s)))))

(fn create-buffers [s]
  (let [buf (vim.api.nvim_create_buf false true)]
    (vim.api.nvim_buf_set_name buf (chat-name s))
    (tset (. vim.bo buf) :swapfile false)
    (tset (. vim.bo buf) :bufhidden :hide)
    (markdown buf)
    (vim.api.nvim_buf_set_lines buf 0 -1 false ["" "" "## You" ""])
    (set s.input-mark (vim.api.nvim_buf_set_extmark buf ns 1 0 {}))
    (vim.api.nvim_buf_set_extmark buf ns 2 0 {:virt_text [["<CR> to send" :Comment]]
                                              :virt_text_pos :eol})
    (vim.api.nvim_buf_call buf #(vim.cmd "syntax sync minlines=200"))
    (set s.held [])
    (set s.attached-blocks {})
    (tset chats buf s)
    (watch-typing s buf)
    (set s.buf buf)))

(fn retitle [s]
  ;; The session moved to another project.
  (when (vim.api.nvim_buf_is_valid s.buf)
    (pcall vim.api.nvim_buf_set_name s.buf (chat-name s))))

(fn visible? [buf]
  (not= -1 (vim.fn.bufwinid buf)))

(fn chat-window-options [win]
  (tset (. vim.wo win) :wrap true)
  (tset (. vim.wo win) :linebreak true)
  (tset (. vim.wo win) :number false)
  (tset (. vim.wo win) :relativenumber false)
  (tset (. vim.wo win) :conceallevel 0)
  ;; Thinking (">> " lines) folds closed; zo / zR open it.
  (tset (. vim.wo win) :foldmethod :expr)
  (tset (. vim.wo win) :foldexpr "getline(v:lnum)=~#'^>>'")
  (tset (. vim.wo win) :foldlevel 0)
  (tset (. vim.wo win) :foldenable true))

(fn line-count [buf]
  (vim.api.nvim_buf_line_count buf))

(fn line-at [buf row0]
  (or (. (vim.api.nvim_buf_get_lines buf row0 (+ row0 1) false) 1) ""))

(fn input-start [s]
  ;; 0-based row of the blank line opening the input area.
  (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns s.input-mark {})]
    (or row (line-count s.buf))))

(fn last-row [s]
  ;; 0-based row of the transcript's last line.
  (- (input-start s) 1))

(fn last-line [s]
  (line-at s.buf (last-row s)))

(fn pristine? [s]
  (and (= (input-start s) 1) (= (last-line s) "")))

(fn input-row [s]
  ;; 1-based row of the first prompt line, just under the heading.
  (+ (input-start s) 3))

(fn in-input? [s row]
  ;; row is 1-based; the heading counts as part of the input area.
  (and row (>= row (+ (input-start s) 2))))

(fn following-windows [s]
  ;; Windows whose cursor is on the transcript's last line follow the stream.
  (let [row (+ (last-row s) 1)]
    (icollect [_ w (ipairs (vim.fn.win_findbuf s.buf))]
      (when (= (. (vim.api.nvim_win_get_cursor w) 1) row) w))))

(fn show [s mods]
  ;; mods are the command modifiers (:tab, :vertical, :botright...); without any,
  ;; the chat opens as a vertical split on the right.
  (if (visible? s.buf)
    (vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
    (do
      (vim.cmd (if (and mods (not= mods "")) (.. mods " split") "botright vsplit"))
      (vim.api.nvim_win_set_buf 0 s.buf)
      (chat-window-options 0))))

(fn cursor-to [s row]
  ;; Moves the chat window's cursor to row (1-based), or to the end of the prompt.
  (let [win (vim.fn.bufwinid s.buf)]
    (when (not= -1 win)
      (let [row (or row (line-count s.buf))]
        (vim.api.nvim_win_set_cursor win [row (length (line-at s.buf (- row 1)))])))))

;; Activity indicator ------------------------------------------------------------
;; Virtual text at the end of the transcript, so it never lands in the buffer text or the log.

(local spinner ["-" "\\" "|" "/"])

(fn activity-text [s]
  (let [a (?. s :activity)]
    (when a
      (let [secs (- (os.time) a.since)]
        (.. (. spinner (+ 1 (% a.frame (length spinner))))
            " " a.label
            (if (> secs 0) (.. " · " secs "s") ""))))))

(fn draw-activity [s]
  (when (and s.buf (vim.api.nvim_buf_is_loaded s.buf))
    (let [text (activity-text s)]
      (if text
        (set s.activity-mark
             (vim.api.nvim_buf_set_extmark s.buf ns (last-row s) 0
                                           {:id s.activity-mark
                                            :virt_text [[text :Comment]]
                                            :virt_text_pos :eol}))
        (when s.activity-mark
          (vim.api.nvim_buf_del_extmark s.buf ns s.activity-mark)
          (set s.activity-mark nil))))))

(fn stop-timer [s]
  (when s.activity-timer
    (s.activity-timer:stop)
    (s.activity-timer:close)
    (set s.activity-timer nil)))

(fn tick [s]
  (when s.activity
    (set s.activity.frame (+ s.activity.frame 1))
    (draw-activity s)
    (vim.cmd "redrawstatus!")))

(fn activity [s label]
  ;; label nil clears the indicator; the elapsed time runs from the first label set.
  (if label
    (do
      (if s.activity
        (set s.activity.label label)
        (set s.activity {: label :since (os.time) :frame 0}))
      (when (not s.activity-timer)
        (set s.activity-timer (vim.uv.new_timer))
        (s.activity-timer:start 150 150 (vim.schedule_wrap #(tick s)))))
    (do
      (set s.activity nil)
      (stop-timer s)))
  (draw-activity s)
  (vim.cmd "redrawstatus!"))

(fn modify [s f]
  ;; Agent changes stay out of undo, so u only ever undoes your own typing.
  (when (vim.api.nvim_buf_is_loaded s.buf)
    (let [buf s.buf
          wins (following-windows s)
          undo-levels (. vim.bo buf :undolevels)]
      (tset (. vim.bo buf) :undolevels -1)
      (f)
      (tset (. vim.bo buf) :undolevels undo-levels)
      (draw-activity s)
      (let [row (+ (last-row s) 1)]
        (each [_ w (ipairs wins)]
          (vim.api.nvim_win_set_cursor w [row 0]))))))

;; Transcript writes all happen at the end of its last line, never at the start of
;; the input area, so the input mark (and anything below) moves down with them.

(fn replace-last [s lines]
  (let [row (last-row s)]
    (vim.api.nvim_buf_set_text s.buf row 0 row (length (line-at s.buf row)) lines)))

(fn append-after [s lines]
  (let [row (last-row s)
        col (length (line-at s.buf row))]
    (vim.api.nvim_buf_set_text s.buf row col row col (vim.list_extend [""] lines))))

(fn joins-previous? [line]
  ;; Quoted lines stack directly under headings and other quoted lines (not thinking).
  (or (= line nil) (= line "") (line:match "^>[^>]") (line:match "^#")))

(fn put-line [s line]
  ;; Puts a standalone line at the end of the transcript, keeping an empty line after
  ;; it for what comes next. Returns the 0-based row it landed on.
  (let [row (last-row s)
        previous (when (> row 0) (line-at s.buf (- row 1)))]
    (if (not= (last-line s) "")
      (append-after s ["" line ""])
      (joins-previous? previous)
      (replace-last s [line ""])
      (replace-last s ["" line ""])))
  (- (last-row s) 1))

(fn status [s message]
  (later s (fn [] (modify s #(put-line s (.. "> acp: " message))))))

(fn begin-turn [s turn]
  (let [lines (vim.list_extend
                [(if turn.time (.. "## You — " turn.time) "## You")]
                (vim.split turn.prompt "\n" {:plain true}))]
    (vim.list_extend lines ["" "## Agent" ""])
    (later s #(modify s
                (fn []
                  (if (pristine? s)
                    (replace-last s lines)
                    (do
                      (when (not= (last-line s) "")
                        (append-after s [""]))
                      (append-after s lines))))))))

(fn append-text [s text]
  (later s #(modify s
              (fn []
                (let [row (last-row s)
                      col (length (last-line s))]
                  (vim.api.nvim_buf_set_text s.buf row col row col
                                             (vim.split text "\n" {:plain true})))))))

(fn add-line [s block]
  (later s #(modify s
              (fn []
                (let [row (put-line s block.line)]
                  (set block.mark (vim.api.nvim_buf_set_extmark s.buf ns row 0 {:right_gravity false})))))))

(fn update-line [s block]
  ;; Checked when it runs: a held add-line has no mark yet.
  (later s #(when block.mark
              (modify s
                (fn []
                  (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns block.mark {})]
                    (when row
                      (let [current (. (vim.api.nvim_buf_get_lines s.buf row (+ row 1) false) 1)]
                        (vim.api.nvim_buf_set_text s.buf row 0 row (length current) [block.line])))))))))

(fn line-row [s block]
  ;; 1-based row of a block's line in the chat, or nil.
  (when (and block block.mark (vim.api.nvim_buf_is_loaded s.buf))
    (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns block.mark {})]
      (when row (+ row 1)))))

;; Tool details ----------------------------------------------------------------------

(fn strip-ansi [text]
  (pick-values 1 (string.gsub text "\27%[[%d;?]*%a" "")))

(fn fence-for [text]
  ;; A fence longer than any backtick run inside, so nested fences survive.
  (var longest 2)
  (each [run (string.gmatch text "`+")]
    (set longest (math.max longest (length run))))
  (string.rep "`" (+ longest 1)))

(fn fenced [lang text]
  (let [text (pick-values 1 (string.gsub text "\n$" ""))
        fence (fence-for text)]
    (vim.list_extend (vim.list_extend [(.. fence lang)] (vim.split text "\n" {:plain true}))
                     [fence ""])))

(fn as-text [value]
  (if (= (type value) :string)
    (strip-ansi value)
    (vim.json.encode value {:indent "  " :sort_keys true})))

(fn with-newline [text]
  ;; Empty stays empty: a new file has no lines before, not one blank one.
  (if (or (= text "") (vim.endswith text "\n")) text (.. text "\n")))

(fn unified-diff [d relative]
  (let [body (vim.text.diff (with-newline d.old) (with-newline d.new)
                            {:result_type :unified :ctxlen 3})]
    (if (vim.startswith relative "/")
      (.. "--- " relative "\n+++ " relative "\n" body)
      (.. "--- a/" relative "\n+++ b/" relative "\n" body))))

(fn relative-path [s path]
  (pick-values 1 (string.gsub (or path "") (vim.pesc (.. s.session.cwd "/")) "")))

(fn diffs-of [details]
  (icollect [_ c (ipairs (or (?. details :content) []))] (when (= c.type :diff) c)))

(fn diff-stats [details]
  ;; Lines added and removed across a tool call's diffs, or nil if it has none.
  (let [diffs (diffs-of details)]
    (when (> (length diffs) 0)
      (var added 0)
      (var removed 0)
      (each [_ d (ipairs diffs)]
        (each [_ l (ipairs (vim.split (vim.text.diff (with-newline d.old) (with-newline d.new)
                                                     {:result_type :unified :ctxlen 0})
                                      "\n" {:plain true}))]
          (if (and (vim.startswith l "+") (not (vim.startswith l "+++")))
            (set added (+ added 1))
            (and (vim.startswith l "-") (not (vim.startswith l "---")))
            (set removed (+ removed 1)))))
      (values added removed))))

(local diff-cap 80)

(fn diff-block [s d cap]
  ;; A fenced unified diff, at most cap lines of it when cap is given.
  (let [relative (relative-path s d.path)
        lines (vim.split (pick-values 1 (string.gsub (unified-diff d relative) "\n$" "")) "\n" {:plain true})
        hidden (if (and cap (> (length lines) cap)) (- (length lines) cap) 0)
        shown (if (> hidden 0) (vim.list_slice lines 1 cap) lines)]
    (when (> hidden 0)
      (table.insert shown (.. "… " hidden " more lines, <CR> on the tool line shows them all")))
    (fenced :diff (table.concat shown "\n"))))

(fn kind-hint [field]
  (case field.kind
    :choice "choice"
    :multichoice "choice, several"
    :boolean "yes/no"
    :number "number"
    :string "text"
    _ "?"))

(fn default-text [field]
  ;; A field's default as it would be answered. Booleans never have one shown
  ;; unless the agent sent it: yes or no.
  (if (= nil (?. field :default)) ""
      (= field.kind :boolean)
      (if field.default "yes" "no")
      (= (type field.default) :table)
      (table.concat (vim.tbl_map tostring field.default) ", ")
      (tostring field.default)))

(fn field-line [field]
  ;; "  notes — Notes (text · optional · default: as-is)"
  (let [parts [(kind-hint field)]]
    (table.insert parts (if field.required? "required" "optional"))
    (when (not= "" (default-text field))
      (table.insert parts (.. "default: " (default-text field))))
    (.. "  " field.name (if field.title (.. " — " field.title) "")
        " (" (table.concat parts " · ") ")")))

(fn elicitation-lines [message fields]
  ;; What goes under an elicitation: the question in full, then each field's
  ;; prompt, with choice values numbered like permission choices. Answers are
  ;; given through the form <CR> or :AcpAnswer opens, so these lines are for
  ;; reading, not pressing.
  (let [lines (vim.split message "\n" {:plain true})]
    (each [_ f (ipairs fields)]
      (table.insert lines "")
      (table.insert lines (field-line f))
      (when f.description (table.insert lines (.. "    " f.description)))
      (each [i o (ipairs (or f.values []))]
        (table.insert lines (.. "  " i ". " o.name
                                (if o.description (.. " — " o.description) "")))))
    lines))

(fn permission-lines [s details full-title kind options]
  ;; What goes under a permission request: the diff being asked for (or the full
  ;; command when its line had to shorten it), then the numbered choices.
  ;; Returns the lines and how many come before the first choice.
  (let [lines []
        diffs (diffs-of details)]
    (each [_ d (ipairs diffs)]
      (table.insert lines "")
      (vim.list_extend lines (diff-block s d diff-cap)))
    (when (and (= 0 (length diffs)) full-title)
      (table.insert lines "")
      (vim.list_extend lines (fenced (if (= kind :execute) "sh" "text") full-title)))
    (let [offset (length lines)]
      (each [i o (ipairs options)]
        (table.insert lines (.. "  " i ". " o.name)))
      (values lines offset))))

(fn tool-sections [s tool heading]
  ;; The detail sections of a tool call, each ending with an empty line.
  ;; heading is the markdown heading marker to use, e.g. "##".
  (let [relative (fn [path] (relative-path s path))
        section (fn [lines title] (table.insert lines (.. heading " " title)))
        details tool.details
        content (or details.content [])
        diffs (icollect [_ c (ipairs content)] (when (= c.type :diff) c))
        texts (icollect [_ c (ipairs content)] (when (= c.type :text) c))
        lines []]
    (when tool.full-title
      (section lines "Title")
      (vim.list_extend lines (fenced "text" tool.full-title)))
    (when (and details.locations (> (length details.locations) 0))
      (section lines "Files")
      (each [_ l (ipairs details.locations)]
        (table.insert lines (.. l.path (if l.line (.. ":" l.line) ""))))
      (table.insert lines ""))
    (each [_ d (ipairs diffs)]
      (section lines (.. "Diff " (relative d.path)))
      (vim.list_extend lines (diff-block s d)))
    (when (> (length texts) 0)
      (section lines "Content")
      (each [_ t (ipairs texts)]
        (vim.list_extend lines (vim.split (strip-ansi t.text) "\n" {:plain true}))
        (table.insert lines "")))
    ;; An edit's input repeats its diff, and text content usually repeats the output.
    (when (and (not= details.input nil) (= (length diffs) 0)
               (not (and (= (type details.input) :table) (= nil (next details.input)))))
      (section lines "Input")
      (vim.list_extend lines (fenced (if (= (type details.input) :string) "text" "json")
                                     (as-text details.input))))
    (when (and (not= details.output nil) (= (length texts) 0))
      (section lines "Output")
      (vim.list_extend lines (fenced (if (= (type details.output) :string) "text" "json")
                                     (as-text details.output))))
    lines))

(fn tool-detail-lines [s tool status-name]
  (vim.list_extend [(.. "# " (or tool.title "tool") " — " status-name)
                    (.. "kind: " (or tool.kind "other"))
                    ""]
                   (tool-sections s tool "##")))

;; Inline expansion: the details as real text under the tool line, so they can be
;; yanked, searched and gF'd. The session log is built from blocks, so it never sees them.

;; Attached lines: real text shown under a block's line (tool details, permission
;; choices, elicitation questions) that isn't part of the turn, so the log never
;; sees it. block.attached is how many lines are attached.
;;
;; They're inserted at the end of the block's line, not at the start of the next
;; line, so the next line's extmark (left gravity at column 0) moves down with them.

(fn line-length [buf row0]
  (length (. (vim.api.nvim_buf_get_lines buf row0 (+ row0 1) false) 1)))

(fn attached? [block]
  (not= nil block.attached))

(fn attach-lines [s block lines]
  (later s
    (fn []
      (let [row (line-row s block)]
        (when (and row (not (attached? block)) (> (length lines) 0))
          (let [row0 (- row 1)
                col (line-length s.buf row0)]
            (modify s #(vim.api.nvim_buf_set_text s.buf row0 col row0 col (vim.list_extend [""] lines)))
            (set block.attached (length lines))
            (tset s.attached-blocks block true)))))))

(fn detach-lines [s block]
  (later s
    (fn []
      (let [row (line-row s block)]
        (when (and row (attached? block))
          (let [row0 (- row 1)
                last0 (+ row0 block.attached)]
            (modify s #(vim.api.nvim_buf_set_text s.buf row0 (line-length s.buf row0)
                                                  last0 (line-length s.buf last0) [""]))
            (set block.attached nil)
            (tset s.attached-blocks block nil)))))))

(fn attached-index [s block row]
  ;; row is 1-based. 0 on the block's own line, 1..n on its attached lines, else nil.
  (let [start (line-row s block)]
    (when (and start (>= row start) (<= row (+ start (or block.attached 0))))
      (- row start))))

;; Section shading -----------------------------------------------------------------
;; Your prompts (and the input area) and the agent's replies get backgrounds of their
;; own, AcpYou and AcpAgent. Worked out at draw time from the headings, so streaming,
;; held writes and expansions can't put it out of step. UI rows (anything starting
;; with ">": tools, permissions, notes, thinking) and the lines attached under them
;; stay plain.

(local shade-ns (vim.api.nvim_create_namespace "acp-shade"))
(local lookahead 50)

(fn heading-kind [line]
  (if (vim.startswith line "## You") :you
      (vim.startswith line "## Agent") :agent))

(fn section-above [buf row]
  ;; The section row (0-based) is in, from the nearest heading above it.
  (var found nil)
  (var to row)
  (while (and (not found) (> to 0))
    (let [from (math.max 0 (- to 200))
          lines (vim.api.nvim_buf_get_lines buf from to false)]
      (for [i (length lines) 1 -1 &until found]
        (set found (heading-kind (. lines i))))
      (set to from)))
  found)

(fn attached-rows [s]
  ;; 0-based rows of lines attached under blocks, as a set.
  (let [rows {}]
    (each [block _ (pairs s.attached-blocks)]
      (let [start (line-row s block)]
        (when start
          (for [r start (+ start (or block.attached 0) -1)]
            (tset rows r true)))))
    rows))

(fn shades [s top bot]
  ;; {row group} for 0-based rows top..bot.
  (let [buf s.buf
        input (- (input-row s) 3)
        last (math.min (+ bot lookahead) (- (line-count buf) 1))
        lines (vim.api.nvim_buf_get_lines buf top (+ last 1) false)
        attached (attached-rows s)
        kinds {}
        start-section (section-above buf top)]
    (var section start-section)
    (each [i line (ipairs lines)]
      (let [row (+ top i -1)
            heading (heading-kind line)]
        (when heading (set section heading))
        (tset kinds row
              (if (>= row (+ input 1)) :you
                  (>= row input) nil
                  (= section :you) :you
                  (not= section :agent) nil
                  (or (vim.startswith line ">") (. attached row)) nil
                  (= line "") :blank
                  :agent))))
    ;; A blank line takes the agent's shade only inside its text, not around UI rows.
    (let [result {}]
      (for [row top bot]
        (let [kind (. kinds row)]
          (if (= kind :blank)
            (do
              (var before (- row 1))
              (while (= (. kinds before) :blank) (set before (- before 1)))
              (var after (+ row 1))
              (while (= (. kinds after) :blank) (set after (+ after 1)))
              (when (and (= (. kinds after) :agent)
                         (or (= (. kinds before) :agent)
                             (and (< before top) (= start-section :agent))))
                (tset result row :AcpAgent)))
            (= kind :you) (tset result row :AcpYou)
            (= kind :agent) (tset result row :AcpAgent))))
      result)))

(vim.api.nvim_set_decoration_provider shade-ns
  {:on_win (fn [_ _ buf top bot]
             (let [s (. chats buf)]
               (if (and s (vim.api.nvim_buf_is_loaded buf))
                 (do (tset drawing buf (shades s top bot)) true)
                 false)))
   :on_line (fn [_ _ buf row]
              (let [group (?. drawing buf row)]
                (when group
                  (vim.api.nvim_buf_set_extmark buf shade-ns row 0
                                                {:end_row (+ row 1) :end_col 0 :hl_group group
                                                 :hl_eol true :ephemeral true :priority 1}))))})

(fn expansion-lines [s tool]
  (let [sections (tool-sections s tool "####")]
    (vim.list_extend [""] (if (> (length sections) 0) sections ["_no details yet_" ""]))))

(fn expanded? [tool]
  (attached? tool.block))

(fn expansion-contains? [s tool row]
  ;; true on the tool line itself or inside its expansion.
  (not= nil (attached-index s tool.block row)))

(fn expand-tool [s tool]
  (attach-lines s tool.block (expansion-lines s tool)))

(fn collapse-tool [s tool]
  (detach-lines s tool.block))

(fn refresh-tool [s tool]
  (when (expanded? tool)
    (collapse-tool s tool)
    (expand-tool s tool)))

(fn open-tool-details [s tool status-name mods]
  (vim.cmd (if (and mods (not= mods "")) (.. mods " new") "new"))
  (let [buf (vim.api.nvim_get_current_buf)]
    (tset (. vim.bo buf) :buftype :nofile)
    (tset (. vim.bo buf) :bufhidden :wipe)
    (tset (. vim.bo buf) :swapfile false)
    (pcall vim.api.nvim_buf_set_name buf (.. "acp://tool/" tool.id))
    (vim.api.nvim_buf_set_lines buf 0 -1 false (tool-detail-lines s tool status-name))
    (tset (. vim.bo buf) :modifiable false)
    (markdown buf)))

(fn prompt-text [s]
  (let [lines (vim.api.nvim_buf_get_lines s.buf (- (input-row s) 1) -1 false)]
    (vim.trim (table.concat lines "\n"))))

(fn clear-prompt [s]
  ;; Your own edit, so it stays undoable.
  (vim.api.nvim_buf_set_lines s.buf (- (input-row s) 1) -1 false [""])
  (cursor-to s (input-row s)))

(fn add-to-prompt [s line]
  ;; Adds a line to the end of the prompt, keeping an empty one after it to type in. A
  ;; cursor on that empty line stays on it. Undoable, like clear-prompt.
  (let [row (- (line-count s.buf) 1)
        empty? (= (line-at s.buf row) "")
        wins (when empty?
               (vim.tbl_filter #(= (. (vim.api.nvim_win_get_cursor $1) 1) (+ row 1))
                               (vim.fn.win_findbuf s.buf)))]
    (vim.api.nvim_buf_set_lines s.buf (if empty? row (+ row 1)) -1 false [line ""])
    (each [_ w (ipairs (or wins []))]
      (vim.api.nvim_win_set_cursor w [(line-count s.buf) 0]))))

(fn wipe [s]
  (set s.activity nil)
  (set s.held [])
  (tset chats s.buf nil)
  (tset drawing s.buf nil)
  (stop-timer s)
  (when (and s.buf (vim.api.nvim_buf_is_valid s.buf))
    (vim.api.nvim_buf_delete s.buf {:force true})))

(local filetype-aliases
  {:clj :clojure :cljs :clojure :cljc :clojure :edn :clojure
   :bash :sh :shell :sh :zsh :sh :console :sh
   :js :javascript :ts :typescript :py :python :fnl :fennel
   :yml :yaml :md :markdown :patch :diff})

(fn fence-at [buf row]
  ;; Returns start, end (1-based, exclusive of fences) and language of the block containing row.
  (let [lines (vim.api.nvim_buf_get_lines buf 0 -1 false)]
    (var open nil)
    (var found nil)
    (each [i line (ipairs lines) &until found]
      (if (not open)
        (let [lang (line:match "^%s*```+%s*([%w_+%-%.]*)")]
          (when lang (set open {:start i : lang})))
        (when (line:match "^%s*```+%s*$")
          (when (and (> row open.start) (< row i))
            (set found {:from (+ open.start 1) :to (- i 1) :lang open.lang}))
          (set open nil))))
    found))

(fn open-code-block []
  (let [buf (vim.api.nvim_get_current_buf)
        row (. (vim.api.nvim_win_get_cursor 0) 1)
        block (fence-at buf row)]
    (if (not block)
      (vim.notify "acp: cursor is not inside a fenced code block" vim.log.levels.WARN)
      (let [lines (vim.api.nvim_buf_get_lines buf (- block.from 1) block.to false)
            lang (string.lower block.lang)
            ft (or (. filetype-aliases lang) lang)]
        (vim.cmd "new")
        (tset (. vim.bo 0) :buftype :nofile)
        (tset (. vim.bo 0) :bufhidden :wipe)
        (tset (. vim.bo 0) :swapfile false)
        (vim.api.nvim_buf_set_lines 0 0 -1 false lines)
        (when (not= ft "")
          (tset (. vim.bo 0) :filetype ft))))))

{: create-buffers
 : retitle
 : markdown
 : show
 : cursor-to
 : in-input?
 : input-row
 : visible?
 : activity
 : activity-text
 : status
 : shades
 : begin-turn
 : append-text
 : add-line
 : update-line
 : line-row
 : open-tool-details
 : diff-stats
 : permission-lines
 : elicitation-lines
 : attach-lines
 : detach-lines
 : attached-index
 : expanded?
 : expansion-contains?
 : expand-tool
 : collapse-tool
 : refresh-tool
 : prompt-text
 : clear-prompt
 : add-to-prompt
 : wipe
 : open-code-block}
