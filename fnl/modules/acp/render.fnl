;; Chat and prompt buffers. Sees session state, never JSON-RPC.

(local ns (vim.api.nvim_create_namespace "acp"))

(fn scratch [name ft]
  (let [buf (vim.api.nvim_create_buf false true)]
    (vim.api.nvim_buf_set_name buf name)
    (tset (. vim.bo buf) :swapfile false)
    (tset (. vim.bo buf) :bufhidden :hide)
    (tset (. vim.bo buf) :filetype ft)
    buf))

(fn create-buffers [s]
  (let [chat (scratch (.. "acp://chat/" s.session.project) :markdown)
        prompt (scratch (.. "acp://prompt/" s.session.project) :markdown)]
    (tset (. vim.bo chat) :modifiable false)
    (vim.api.nvim_buf_call chat #(vim.cmd "syntax sync minlines=200"))
    (set s.buf chat)
    (set s.prompt-buf prompt)))

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

(fn open-prompt-below []
  (vim.cmd "belowright 8split")
  (tset (. vim.wo 0) :winfixheight true)
  (tset (. vim.wo 0) :number false)
  (tset (. vim.wo 0) :relativenumber false))

(fn show [s mods]
  ;; mods are the command modifiers (:tab, :vertical, :botright...); without any,
  ;; the chat opens as a vertical split on the right.
  (if (visible? s.buf)
    (if (visible? s.prompt-buf)
      (vim.api.nvim_set_current_win (vim.fn.bufwinid s.prompt-buf))
      (do
        (vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
        (open-prompt-below)
        (vim.api.nvim_win_set_buf 0 s.prompt-buf)))
    (visible? s.prompt-buf)
    (let [prompt-win (vim.fn.bufwinid s.prompt-buf)]
      (vim.api.nvim_set_current_win prompt-win)
      (vim.cmd "aboveleft split")
      (vim.api.nvim_win_set_buf 0 s.buf)
      (chat-window-options 0)
      (vim.cmd "normal! G")
      (vim.api.nvim_set_current_win prompt-win)
      (vim.api.nvim_win_set_height prompt-win 8)
      (tset (. vim.wo prompt-win) :winfixheight true))
    (do
      (vim.cmd (if (and mods (not= mods "")) (.. mods " split") "botright vsplit"))
      (vim.api.nvim_win_set_buf 0 s.buf)
      (chat-window-options 0)
      (vim.cmd "normal! G")
      (open-prompt-below)
      (vim.api.nvim_win_set_buf 0 s.prompt-buf))))

(fn line-count [buf]
  (vim.api.nvim_buf_line_count buf))

(fn last-line [buf]
  (let [n (line-count buf)]
    (. (vim.api.nvim_buf_get_lines buf (- n 1) n false) 1)))

(fn pristine? [buf]
  (and (= (line-count buf) 1) (= (last-line buf) "")))

(fn following-windows [buf]
  ;; Only windows whose cursor is already on the last line follow the stream.
  (let [n (line-count buf)]
    (icollect [_ w (ipairs (vim.fn.win_findbuf buf))]
      (when (= (. (vim.api.nvim_win_get_cursor w) 1) n) w))))

;; Activity indicator ------------------------------------------------------------
;; Virtual text at the end of the chat, so it never lands in the buffer text or the log.

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
             (vim.api.nvim_buf_set_extmark s.buf ns (- (line-count s.buf) 1) 0
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
  (when (vim.api.nvim_buf_is_loaded s.buf)
    (let [buf s.buf
          wins (following-windows buf)]
      (tset (. vim.bo buf) :modifiable true)
      (f)
      (tset (. vim.bo buf) :modifiable false)
      (draw-activity s)
      (let [n (line-count buf)]
        (each [_ w (ipairs wins)]
          (vim.api.nvim_win_set_cursor w [n 0]))))))

(fn replace-last [buf lines]
  (let [n (line-count buf)]
    (vim.api.nvim_buf_set_lines buf (- n 1) n false lines)))

(fn append-after [buf lines]
  (vim.api.nvim_buf_set_lines buf -1 -1 false lines))

(fn joins-previous? [line]
  ;; Quoted lines stack directly under headings and other quoted lines (not thinking).
  (or (= line nil) (= line "") (line:match "^>[^>]") (line:match "^#")))

(fn put-line [buf line]
  ;; Puts a standalone line at the end, keeping an empty line after it for what comes next.
  ;; Returns the 0-based row it landed on.
  (let [n (line-count buf)
        previous (when (> n 1) (. (vim.api.nvim_buf_get_lines buf (- n 2) (- n 1) false) 1))]
    (if (not= (last-line buf) "")
      (append-after buf ["" line ""])
      (joins-previous? previous)
      (replace-last buf [line ""])
      (replace-last buf ["" line ""])))
  (- (line-count buf) 2))

(fn status [s message]
  (modify s
    #(put-line s.buf (.. "> acp: " message))))

(fn begin-turn [s turn]
  (let [lines (vim.list_extend
                [(.. "## You — " turn.time)]
                (vim.split turn.prompt "\n" {:plain true}))]
    (vim.list_extend lines ["" "## Agent" ""])
    (modify s
      (fn []
        (if (pristine? s.buf)
          (replace-last s.buf lines)
          (do
            (when (not= (last-line s.buf) "")
              (append-after s.buf [""]))
            (append-after s.buf lines)))))))

(fn append-text [s text]
  (modify s
    (fn []
      (let [row (- (line-count s.buf) 1)
            col (length (last-line s.buf))]
        (vim.api.nvim_buf_set_text s.buf row col row col
                                   (vim.split text "\n" {:plain true}))))))

(fn add-line [s block]
  (modify s
    (fn []
      (let [row (put-line s.buf block.line)]
        (set block.mark (vim.api.nvim_buf_set_extmark s.buf ns row 0 {:right_gravity false}))))))

(fn update-line [s block]
  (when block.mark
    (modify s
      (fn []
        (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns block.mark {})]
          (when row
            (let [current (. (vim.api.nvim_buf_get_lines s.buf row (+ row 1) false) 1)]
              (vim.api.nvim_buf_set_text s.buf row 0 row (length current) [block.line]))))))))

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
  (if (vim.endswith text "\n") text (.. text "\n")))

(fn unified-diff [d relative]
  (let [body (vim.text.diff (with-newline d.old) (with-newline d.new)
                            {:result_type :unified :ctxlen 3})]
    (if (vim.startswith relative "/")
      (.. "--- " relative "\n+++ " relative "\n" body)
      (.. "--- a/" relative "\n+++ b/" relative "\n" body))))

(fn tool-sections [s tool heading]
  ;; The detail sections of a tool call, each ending with an empty line.
  ;; heading is the markdown heading marker to use, e.g. "##".
  (let [cwd-prefix (.. s.session.cwd "/")
        relative (fn [path] (pick-values 1 (string.gsub (or path "") (vim.pesc cwd-prefix) "")))
        section (fn [lines title] (table.insert lines (.. heading " " title)))
        details tool.details
        content (or details.content [])
        diffs (icollect [_ c (ipairs content)] (when (= c.type :diff) c))
        texts (icollect [_ c (ipairs content)] (when (= c.type :text) c))
        lines []]
    (when (and details.locations (> (length details.locations) 0))
      (section lines "Files")
      (each [_ l (ipairs details.locations)]
        (table.insert lines (.. l.path (if l.line (.. ":" l.line) ""))))
      (table.insert lines ""))
    (each [_ d (ipairs diffs)]
      (section lines (.. "Diff " (relative d.path)))
      (vim.list_extend lines (fenced :diff (unified-diff d (relative d.path)))))
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

(fn expansion-lines [s tool]
  (let [sections (tool-sections s tool "####")]
    (vim.list_extend [""] (if (> (length sections) 0) sections ["_no details yet_" ""]))))

(fn expanded? [tool]
  (not= nil tool.block.expanded))

(fn expansion-contains? [s tool row]
  ;; row is 1-based; true on the tool line itself or inside its expansion.
  (let [start (line-row s tool.block)]
    (and start (>= row start) (<= row (+ start (or tool.block.expanded 0))))))

;; Expansions are inserted at the end of the tool line, not at the start of the next
;; line, so the next line's extmark (left gravity at column 0) moves down with it.

(fn line-length [buf row0]
  (length (. (vim.api.nvim_buf_get_lines buf row0 (+ row0 1) false) 1)))

(fn expand-tool [s tool]
  (let [row (line-row s tool.block)]
    (when (and row (not (expanded? tool)))
      (let [lines (expansion-lines s tool)
            row0 (- row 1)
            col (line-length s.buf row0)]
        (modify s #(vim.api.nvim_buf_set_text s.buf row0 col row0 col (vim.list_extend [""] lines)))
        (set tool.block.expanded (length lines))))))

(fn collapse-tool [s tool]
  (let [row (line-row s tool.block)]
    (when (and row (expanded? tool))
      (let [row0 (- row 1)
            last0 (+ row0 tool.block.expanded)]
        (modify s #(vim.api.nvim_buf_set_text s.buf row0 (line-length s.buf row0)
                                              last0 (line-length s.buf last0) [""]))
        (set tool.block.expanded nil)))))

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
    (tset (. vim.bo buf) :filetype :markdown)))

(fn prompt-text [s]
  (let [lines (vim.api.nvim_buf_get_lines s.prompt-buf 0 -1 false)]
    (vim.trim (table.concat lines "\n"))))

(fn clear-prompt [s]
  (vim.api.nvim_buf_set_lines s.prompt-buf 0 -1 false []))

(fn wipe [s]
  (set s.activity nil)
  (stop-timer s)
  (each [_ buf (ipairs [s.prompt-buf s.buf])]
    (when (and buf (vim.api.nvim_buf_is_valid buf))
      (vim.api.nvim_buf_delete buf {:force true}))))

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
 : show
 : visible?
 : activity
 : activity-text
 : status
 : begin-turn
 : append-text
 : add-line
 : update-line
 : line-row
 : open-tool-details
 : expanded?
 : expansion-contains?
 : expand-tool
 : collapse-tool
 : refresh-tool
 : prompt-text
 : clear-prompt
 : wipe
 : open-code-block}
