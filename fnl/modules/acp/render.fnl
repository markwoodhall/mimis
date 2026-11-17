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

(local image (require :modules.acp.image))

(local ns (vim.api.nvim_create_namespace "acp"))

(fn markdown [buf]
  ;; The bundled markdown ftplugin starts treesitter, which leaves ```diff blocks
  ;; uncoloured without a diff parser; vim syntax colours them via
  ;; markdown_fenced_languages.
  ;; markdown.vim's own concealing stays off, as it blanks whole fence lines; the chat's
  ;; own rules on top, syntax/acpchat.vim, hide the inline markers instead.
  (let [conceal vim.g.markdown_syntax_conceal]
    (set vim.g.markdown_syntax_conceal 0)
    (tset (. vim.bo buf) :filetype :markdown)
    (pcall vim.treesitter.stop buf)
    (tset (. vim.bo buf) :syntax :markdown)
    (set vim.g.markdown_syntax_conceal conceal))
  (vim.api.nvim_buf_call buf #(vim.cmd "runtime! syntax/acpchat.vim")))

(fn chat-name [s]
  ;; A delegated session shares its project with its parent, so it needs its label too.
  (.. "acp://chat/" s.session.project (if s.label (.. "/" s.label) "")))

(local chats {})
;; Shades worked out for each chat buffer in its current redraw, and its attached rows.
(local drawing {})
(local drawing-attached {})
;; Lays the chat's tables out again for its window's width; see Tables below.
(var fit-tables nil)
;; Shows which choice the cursor is on; see Choices below.
(var show-selection nil)
;; Sends the chat's images to the terminal again; see Inline images.
(var resend-images nil)

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
    ;; nil, as a callback that returns something true is deleted.
    (on [:CursorMoved :CursorMovedI] #(do (show-selection s) nil))
    (on :CursorHoldI #(when (= 0 (vim.fn.pumvisible))
                        (set s.typing-paused true)
                        (flush s)))
    ;; Tables wrap their cells to the window, so a new width lays them out again.
    ;; Scheduled, so a window just opened has its options (no number column) by then.
    (on :BufWinEnter #(vim.schedule #(do (fit-tables s) (resend-images s))))
    (vim.api.nvim_create_autocmd [:WinResized :VimResized]
      {: group
       :callback #(if (vim.api.nvim_buf_is_valid buf)
                    (do (fit-tables s) nil)
                    true)})
    ;; Back from another tmux window or application: the images may never have
    ;; reached the terminal while the chat was out of sight.
    (vim.api.nvim_create_autocmd :FocusGained
      {: group
       :callback #(if (vim.api.nvim_buf_is_valid buf)
                    (do (resend-images s) nil)
                    true)})))

(fn create-buffers [s]
  (let [buf (vim.api.nvim_create_buf false true)]
    (vim.api.nvim_buf_set_name buf (chat-name s))
    (tset (. vim.bo buf) :swapfile false)
    (tset (. vim.bo buf) :bufhidden :hide)
    (markdown buf)
    (vim.api.nvim_buf_set_lines buf 0 -1 false ["" "" "## You" ""])
    (set s.input-mark (vim.api.nvim_buf_set_extmark buf ns 1 0 {}))
    (set s.held [])
    (set s.tables [])
    (set s.diagrams [])
    (set s.images [])
    (set s.rules [])
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
  ;; For the chat in win only, as :setlocal: the chat often opens in the window you
  ;; were in, and the buffer you go back to there keeps its own options.
  (let [setlocal (fn [name value]
                   (vim.api.nvim_set_option_value name value {:scope :local : win}))]
    (setlocal :wrap true)
    (setlocal :linebreak true)
    (setlocal :number false)
    (setlocal :relativenumber false)
    ;; For the UI rows' labels, see decorate; the cursor's line shows them in full.
    (setlocal :conceallevel 2)
    (setlocal :concealcursor "")
    ;; Headings bold in their colours, bold text and code in colours of their own,
    ;; and folded thinking muted, here only.
    (setlocal :winhighlight
              (table.concat (vim.list_extend (fcollect [level 1 6] (.. "markdownH" level ":AcpH" level))
                                             ["markdownBold:AcpBold" "markdownCode:AcpCode"
                                              "Folded:AcpFolded"])
                            ","))
    ;; Thinking (">> " lines) folds closed; zo / zR open it.
    (setlocal :foldmethod :expr)
    ;; Diagrams fold away their source too, see fold.
    (setlocal :foldexpr "v:lua.require'modules.acp.render'.fold(v:lnum)")
    (setlocal :foldlevel 0)
    (setlocal :foldenable true)
    ;; A bar beside your prompts, see gutter: a three-column fold column gives the
    ;; status column its width, and gutter draws it instead.
    (setlocal :foldcolumn "3")
    (setlocal :statuscolumn "%!v:lua.require'modules.acp.render'.gutter()")))

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
  ;; mods are the command modifiers (:tab, :vertical, :botright...), which open the
  ;; chat in a new window; without any, it takes the current one. Already showing,
  ;; its window is focused.
  (if (visible? s.buf)
    (vim.api.nvim_set_current_win (vim.fn.bufwinid s.buf))
    (do
      (when (and mods (not= mods ""))
        (vim.cmd (.. mods " split")))
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

;; Tables -----------------------------------------------------------------------------
;; Agents pad markdown tables loosely, if at all. Once a table's rows are complete
;; (the line after it has begun, or something else is put under it) its columns are
;; padded to the widest cell, display width, so it reads as a grid. Only the table
;; that just ended is looked at, and only in the agent's text, not in code blocks.

(fn table-row? [line]
  (not= nil (line:match "^%s*|.*|%s*$")))

(fn table-cells [line]
  ;; Splits on | outside `code` and not escaped as \|.
  (let [body (-> line (vim.trim) (: :gsub "^|" "") (: :gsub "|$" ""))
        cells []]
    (var cell "")
    (var code? false)
    (var i 1)
    (while (<= i (length body))
      (let [c (body:sub i i)]
        (if (and (= c "\\") (= (body:sub (+ i 1) (+ i 1)) "|"))
          (do (set cell (.. cell "\\|")) (set i (+ i 1)))
          (= c "`")
          (do (set code? (not code?)) (set cell (.. cell c)))
          (and (= c "|") (not code?))
          (do (table.insert cells (vim.trim cell)) (set cell ""))
          (set cell (.. cell c))))
      (set i (+ i 1)))
    (table.insert cells (vim.trim cell))
    cells))

(fn rule-cell? [cell]
  (not= nil (cell:match "^:?%-+:?$")))

(fn rule? [cells]
  (accumulate [all true _ c (ipairs cells)] (and all (rule-cell? c))))

(fn width-of [text]
  ;; Width as shown, with the markers syntax/acpchat.vim conceals left out: code spans'
  ;; backticks (what's inside them is shown as is), link brackets and URLs, and bold,
  ;; italic and struck-out markers. A row on the cursor's line shows them, and is
  ;; wider for it.
  (let [shown (-> text
                  (: :gsub "(`+)(.-)%1" #(string.rep "x" (vim.fn.strdisplaywidth $2)))
                  (: :gsub "!?%[(.-)%]%b()" "%1")
                  (: :gsub "%*%*%*(%S.-)%*%*%*" "%1")
                  (: :gsub "%*%*(%S.-)%*%*" "%1")
                  (: :gsub "__(%S.-)__" "%1")
                  (: :gsub "~~(%S.-)~~" "%1")
                  (: :gsub "%*(%S.-)%*" "%1"))]
    (vim.fn.strdisplaywidth shown)))

(fn cell-tokens [text]
  ;; A cell's words. A `code span` with spaces in it is a word for each, each its own
  ;; span, so it can break like the rest; next to each other they look the same.
  (let [tokens []]
    (var token "")
    (var code? false)
    (for [i 1 (length text)]
      (let [c (text:sub i i)]
        (when (= c "`") (set code? (not code?)))
        (if (= c " ")
          (do (when (not= token "")
                (table.insert tokens (if code? (.. token "`") token)))
              (set token (if code? "`" "")))
          (set token (.. token c)))))
    (when (and (not= token "") (not= token "`")) (table.insert tokens token))
    tokens))

(fn split-token [token width]
  ;; A word wider than its column, in pieces that fit. A code span stays code in each
  ;; piece, as an unclosed backtick would colour the rest of the table.
  (let [code? (and (> (length token) 2) (vim.startswith token "`") (vim.endswith token "`"))
        inner (if code? (token:sub 2 -2) token)
        room (math.max 1 (if code? (- width 2) width))
        pieces []]
    (var piece "")
    (each [_ ch (ipairs (vim.fn.split inner "\\zs"))]
      (when (and (not= piece "") (> (width-of (.. piece ch)) room))
        (table.insert pieces piece)
        (set piece ""))
      (set piece (.. piece ch)))
    (table.insert pieces piece)
    (if code?
      (icollect [_ p (ipairs pieces)] (.. "`" p "`"))
      pieces)))

(fn wrap-cell [text width]
  ;; A cell's text as lines no wider than width, broken between words.
  (let [lines []]
    (var line "")
    (each [_ token (ipairs (cell-tokens text))]
      (each [_ piece (ipairs (if (> (width-of token) width) (split-token token width) [token]))]
        (if (= line "") (set line piece)
            (<= (width-of (.. line " " piece)) width) (set line (.. line " " piece))
            (do (table.insert lines line)
                (set line piece)))))
    (table.insert lines line)
    lines))

(fn sum [xs]
  (accumulate [total 0 _ x (ipairs xs)] (+ total x)))

(fn fit-widths [natural floors room]
  ;; Each column gets its floor, then what's left of room goes to the columns in
  ;; proportion to how much more they'd take, so a column of long text gets the most.
  (let [spare (math.max 0 (- room (sum floors)))
        wants (icollect [i n (ipairs natural)] (- n (. floors i)))
        wanted (sum wants)
        widths (icollect [i f (ipairs floors)]
                 (+ f (if (> wanted 0) (math.floor (/ (* spare (. wants i)) wanted)) 0)))]
    ;; What rounding left over, a cell each to the columns still short.
    (var left (- (math.min room (sum natural)) (sum widths)))
    (each [i w (ipairs widths)]
      (when (and (> left 0) (< w (. natural i)))
        (tset widths i (+ w 1))
        (set left (- left 1))))
    widths))

(fn lay-out-rows [rows max-width]
  ;; The table's rows (lists of cells, the rule second) as lines padded to even
  ;; columns. Wider than max-width, if given, its widest columns narrow and their cells
  ;; wrap onto rows of their own, as long as a column can keep its longest word whole
  ;; (up to an even share of the width).
  (do
      (let [columns (accumulate [n 0 _ r (ipairs rows)] (math.max n (length r)))
            aligns (fcollect [i 1 columns]
                     (let [c (or (. rows 2 i) "-")]
                       (if (and (vim.startswith c ":") (vim.endswith c ":")) :center
                           (vim.endswith c ":") :right
                           :left)))
            natural (fcollect [i 1 columns]
                      (accumulate [w 3 ri r (ipairs rows)]
                        (if (= ri 2) w (math.max w (width-of (or (. r i) ""))))))
            room (if max-width (- max-width (+ (* 3 columns) 1)) math.huge)
            ;; A column's floor is its longest word, kept whole if every column's
            ;; can be, else capped at an even share of the room.
            words (fcollect [i 1 columns]
                    (math.min (. natural i)
                              (accumulate [w 3 ri r (ipairs rows)]
                                (if (= ri 2) w
                                    (accumulate [w w _ t (ipairs (cell-tokens (or (. r i) "")))]
                                      (math.max w (width-of t)))))))
            share (math.max 3 (math.floor (/ room columns)))
            floors (if (<= (sum words) room)
                     words
                     (icollect [_ w (ipairs words)] (math.min w share)))
            widths (if (<= (sum natural) room)
                     natural
                     (fit-widths natural floors room))
            pad (fn [text width align]
                  (let [gap (- width (width-of text))
                        left (case align :right gap :center (math.floor (/ gap 2)) _ 0)]
                    (.. (string.rep " " left) text (string.rep " " (- gap left)))))
            rule-segment (fn [width align]
                           (case align
                             :center (.. ":" (string.rep "-" width) ":")
                             :right (.. "-" (string.rep "-" width) ":")
                             _ (string.rep "-" (+ width 2))))]
        (let [out []]
          (each [ri r (ipairs rows)]
            (if (= ri 2)
              (table.insert out (.. "|" (table.concat (fcollect [i 1 columns]
                                                        (rule-segment (. widths i) (. aligns i)))
                                                      "|") "|"))
              (let [cells (fcollect [i 1 columns] (wrap-cell (or (. r i) "") (. widths i)))
                    height (accumulate [h 1 _ c (ipairs cells)] (math.max h (length c)))]
                (for [k 1 height]
                  (table.insert out (.. "| " (table.concat (fcollect [i 1 columns]
                                                             (pad (or (. cells i k) "") (. widths i) (. aligns i)))
                                                           " | ") " |"))))))
          out))))

(fn aligned-table [lines max-width]
  ;; The table's lines laid out, or nil if it isn't a table: a header row then a rule
  ;; of dashes. Widths are as shown, with markers concealed, but 'linebreak' breaks a
  ;; line by its whole width, so a row whose markers take it past max-width would
  ;; still break: laid out again a column narrower until none does, the widest that
  ;; fits, giving up after 30.
  (let [rows (icollect [_ l (ipairs lines)] (table-cells l))
        fits? (fn [out]
                (accumulate [ok true _ l (ipairs out)]
                  (and ok (<= (vim.fn.strdisplaywidth l) max-width))))]
    (when (and (>= (length rows) 2) (rule? (. rows 2)))
      (var out (lay-out-rows rows max-width))
      (when max-width
        (var width max-width)
        (while (and (not (fits? out)) (> width (math.max 20 (- max-width 30))))
          (set width (- width 1))
          (set out (lay-out-rows rows width))))
      out)))

(fn in-code-block? [buf row]
  ;; Whether row (0-based) is inside a fenced block, counting fences back to the
  ;; ## You or ## Agent heading that opens its section.
  (var fences 0)
  (var r (- row 1))
  (var done false)
  (while (and (not done) (>= r 0))
    (let [line (line-at buf r)]
      (if (or (vim.startswith line "## You") (vim.startswith line "## Agent")) (set done true)
          (line:match "^%s*```") (set fences (+ fences 1))))
    (set r (- r 1)))
  (= 1 (% fences 2)))

;; A laid-out table can't be laid out again from what's in the buffer, once its cells
;; are wrapped, so each keeps the rows it came as in s.tables, with a mark on its first
;; line and how many lines it takes, to lay it out again for a new width.

(fn table-width [s]
  ;; The chat window's text width, else the last one known; nil for no limit.
  (let [win (vim.fn.bufwinid s.buf)]
    (when (not= -1 win)
      (let [info (. (vim.fn.getwininfo win) 1)]
        (set s.table-width (- info.width info.textoff))))
    s.table-width))

(fn table-at [s top]
  (accumulate [found nil _ t (ipairs s.tables) &until found]
    (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns t.mark {})]
      (when (= row top) t))))

(fn lay-out [s top bottom source entry]
  ;; Replaces rows top..bottom (0-based, inclusive) with source laid out, and
  ;; remembers it. Returns false if source isn't a table.
  (let [layout (aligned-table source (table-width s))]
    (when layout
      (when (not (vim.deep_equal layout (vim.api.nvim_buf_get_lines s.buf top (+ bottom 1) false)))
        (vim.api.nvim_buf_set_lines s.buf top (+ bottom 1) false layout))
      (let [t (or entry (let [t {}] (table.insert s.tables t) t))]
        (set t.mark (vim.api.nvim_buf_set_extmark s.buf ns top 0 {:id t.mark}))
        (set t.source source)
        (set t.height (length layout))))
    (not= nil layout)))

(fn align-table-above [s row]
  ;; Aligns the table whose last row is row (0-based), if there is one: from the rows
  ;; it came as, if it was laid out before, and the rows added since.
  (let [buf s.buf]
    (when (and (>= row 0) (table-row? (line-at buf row)))
      (var top row)
      (while (and (> top 0) (table-row? (line-at buf (- top 1))))
        (set top (- top 1)))
      (when (not (in-code-block? buf top))
        (let [entry (table-at s top)
              lines (vim.api.nvim_buf_get_lines buf top (+ row 1) false)
              source (if entry
                       (vim.list_extend (vim.deepcopy entry.source)
                                        (vim.list_slice lines (+ entry.height 1)))
                       lines)]
          (lay-out s top row source entry))))))

(fn reflow-tables [s]
  ;; Lays every table out again, for a new width. A table that isn't where it was
  ;; (edited away) is forgotten.
  (set s.tables
       (icollect [_ t (ipairs s.tables)]
         (let [[top] (vim.api.nvim_buf_get_extmark_by_id s.buf ns t.mark {})]
           (when (and top (table-row? (line-at s.buf top))
                      (lay-out s top (+ top t.height -1) t.source t))
             t)))))

;; Diagrams ---------------------------------------------------------------------------
;; A ```mermaid block is drawn once its closing fence arrives: as an image where the
;; terminal shows them and mmdc is there (see image.fnl), else as text by
;; vim.g.acp-mermaid-cmd (mermaid-ascii by default) reading it on stdin. The drawing
;; goes under the block as virtual lines, and the block folds away: zo shows the
;; source. The buffer's text doesn't change. If nothing can draw it, the block stays
;; as it is. s.diagrams holds a mark on the line after each block and how many lines
;; the block takes, and for an image its file, pixel size, id and size in cells.

(local diagram-ns (vim.api.nvim_create_namespace "acp-diagram"))

(fn mermaid-block [buf row]
  ;; If row (0-based) closes a ```mermaid block: the block's first row and its source.
  (when (and (: (line-at buf row) :match "^%s*```+%s*$") (in-code-block? buf row))
    (var top (- row 1))
    (while (and (>= top 0) (not (: (line-at buf top) :match "^%s*```")))
      (set top (- top 1)))
    (when (and (>= top 0) (: (line-at buf top) :match "^%s*```+%s*mermaid%s*$"))
      (values top (vim.api.nvim_buf_get_lines buf (+ top 1) row false)))))

(fn drawing-lines [stdout]
  (let [lines (icollect [_ l (ipairs (vim.split stdout "\n" {:plain true}))]
                (pick-values 1 (l:gsub "%s+$" "")))]
    (while (and (> (length lines) 0) (= "" (. lines (length lines))))
      (table.remove lines))
    lines))

(fn place-diagram [s d virt-lines]
  ;; Shows virt-lines (each a list of [text group] chunks) under the diagram's block,
  ;; and folds the block.
  (let [[after] (vim.api.nvim_buf_get_extmark_by_id s.buf diagram-ns d.mark {})]
    (when after
      (vim.api.nvim_buf_set_extmark s.buf diagram-ns after 0
                                    {:id d.mark :virt_lines virt-lines :virt_lines_above true})
      (when (not d.drawn)
        (set d.drawn true)
        ;; Folds are worked out again only for changed lines, so the block is
        ;; rewritten as it is for its fold to close.
        (let [top (- after d.height)]
          (vim.api.nvim_buf_set_lines s.buf top after false
                                      (vim.api.nvim_buf_get_lines s.buf top after false)))))))

(fn draw-text [s d source]
  ;; The diagram drawn as text, by vim.g.acp-mermaid-cmd.
  (let [cmd (or vim.g.acp-mermaid-cmd ["mermaid-ascii" "-f" "-"])]
    (when (= 1 (vim.fn.executable (. cmd 1)))
      (pcall vim.system cmd {:stdin (table.concat source "\n") :text true}
             (vim.schedule_wrap
               (fn [result]
                 (let [lines (drawing-lines (or result.stdout ""))]
                   (when (and (= result.code 0) (> (length lines) 0)
                              (vim.api.nvim_buf_is_loaded s.buf))
                     (later s #(modify s #(place-diagram s d (icollect [_ l (ipairs lines)]
                                                               [[l :AcpDiagram]]))))))))))))

(fn image-lines [s img]
  ;; The placeholder lines of an image ({: path : size :scale :max-rows}) at the
  ;; chat's width now, placing it again if its size in cells changed.
  (let [(cols rows) (image.cells img.size (or img.scale 1)
                                 (math.max 10 (- (or (table-width s) 80) 2))
                                 img.max-rows)]
    (when (or (not= cols img.cols) (not= rows img.rows))
      (if img.id
        (image.place img.id cols rows)
        (set img.id (image.show img.path cols rows)))
      (set img.cols cols)
      (set img.rows rows))
    (image.lines img.id cols rows)))

(fn draw-image [s d source]
  ;; The diagram drawn as an image by mmdc, else as text.
  (image.render-mermaid (table.concat source "\n")
    (fn [path]
      (let [size (when path (image.png-size path))]
        (if (and size (vim.api.nvim_buf_is_loaded s.buf))
          (do (set d.image {: path : size :scale 2})
              (later s #(modify s #(place-diagram s d (image-lines s d.image)))))
          (draw-text s d source))))))

(fn draw-diagram [s row]
  ;; Draws the diagram whose block closes at row (0-based), if it is one.
  (let [(top source) (mermaid-block s.buf row)]
    (when top
      (let [d {:mark (vim.api.nvim_buf_set_extmark s.buf diagram-ns (+ row 1) 0 {})
               :height (+ (- row top) 1)}]
        (table.insert s.diagrams d)
        (if (and (image.supported?) (image.mermaid?))
          (draw-image s d source)
          (draw-text s d source))))))

;; Inline images ----------------------------------------------------------------------
;; ![alt](path) in the agent's text, a local file, shows as an image under its line,
;; as wide as the chat allows and no taller than a third of its window. A path is the
;; session directory's if it isn't absolute or ~, and may start file://. Not a PNG,
;; it's made one by magick. A web address, a file that isn't there, or a terminal
;; without images leaves the line as it is, its alt text showing. s.images holds a
;; mark on each line and the image's file, pixel size, id and size in cells.

(local image-ns (vim.api.nvim_create_namespace "acp-image"))

(fn image-paths [s line]
  (icollect [target (line:gmatch "!%[[^%]]*%]%(%s*<?([^%s%)>]+)>?[^%)]*%)")]
    (let [path (target:gsub "^file://" "")]
      (when (not (path:match "^%a[%w+.-]*://"))
        (let [full (if (or (vim.startswith path "/") (vim.startswith path "~"))
                     (vim.fn.expand path)
                     (.. (or (?. s :session :cwd) (vim.fn.getcwd)) "/" path))]
          (when (= 1 (vim.fn.filereadable full)) full))))))

(fn image-rows [s]
  ;; A third of the chat window's height, or of the editor's if it isn't showing.
  (let [win (vim.fn.bufwinid s.buf)]
    (math.max 4 (math.floor (/ (if (= -1 win) vim.o.lines (vim.api.nvim_win_get_height win)) 3)))))

(fn place-images [s entry]
  (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf image-ns entry.mark {})]
    (when row
      (vim.api.nvim_buf_set_extmark
        s.buf image-ns row 0
        {:id entry.mark
         :virt_lines (accumulate [lines [] _ img (ipairs entry.images)]
                       (vim.list_extend lines (image-lines s img)))}))))

(fn show-images [s row]
  ;; Shows the images the line at row (0-based) names, once it's complete.
  (when (and (image.supported?) (not (in-code-block? s.buf row)))
    (let [paths (image-paths s (line-at s.buf row))]
      (when (> (length paths) 0)
        (let [entry {:mark (vim.api.nvim_buf_set_extmark s.buf image-ns row 0 {}) :images []}]
          (table.insert s.images entry)
          (each [_ path (ipairs paths)]
            (image.as-png path
              (fn [png]
                (let [size (when png (image.png-size png))]
                  (when (and size (vim.api.nvim_buf_is_loaded s.buf))
                    (table.insert entry.images {:path png : size :max-rows (image-rows s)})
                    (later s #(modify s #(place-images s entry)))))))))))))

;; Heading rules ----------------------------------------------------------------------
;; A faint line under the agent's # and ## headings, the chat's width, as a virtual
;; line. Not under a turn's own ## You or ## Agent. s.rules holds a mark on each.

(local rule-ns (vim.api.nvim_create_namespace "acp-rule"))

(fn place-rule [s mark]
  (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf rule-ns mark {})]
    (when row
      (vim.api.nvim_buf_set_extmark s.buf rule-ns row 0
                                    {:id mark
                                     :virt_lines [[[(string.rep "─" (or (table-width s) 80))
                                                    :AcpHeadingRule]]]}))))

(fn rule-heading [s row]
  ;; Rules the line at row (0-based) if it's one of the agent's # or ## headings.
  (let [line (line-at s.buf row)]
    (when (and (line:match "^ ? ? ?##? ")
               (not (line:match "^## You"))
               (not (line:match "^## Agent"))
               (not (in-code-block? s.buf row)))
      (let [mark (vim.api.nvim_buf_set_extmark s.buf rule-ns row 0 {})]
        (table.insert s.rules mark)
        (place-rule s mark)))))

(fn refit-images [s]
  ;; Images and heading rules at the chat's new width.
  (each [_ mark (ipairs s.rules)]
    (place-rule s mark))
  (each [_ d (ipairs s.diagrams)]
    (when (and d.drawn d.image)
      (place-diagram s d (image-lines s d.image))))
  (each [_ entry (ipairs s.images)]
    (when (> (length entry.images) 0)
      (place-images s entry))))

(set resend-images
     (fn [s]
       ;; Every image the chat shows, sent again, for when the terminal hasn't got
       ;; them: see image.resend.
       (when (and (vim.api.nvim_buf_is_loaded s.buf) (visible? s.buf) (image.supported?))
         (each [_ d (ipairs s.diagrams)]
           (let [img d.image]
             (when (and d.drawn img img.id)
               (image.resend img.path img.id img.cols img.rows))))
         (each [_ entry (ipairs s.images)]
           (each [_ img (ipairs entry.images)]
             (when img.id
               (image.resend img.path img.id img.cols img.rows)))))))

(set fit-tables
     (fn [s]
       ;; When the chat window's width changes: tables lay out again, images resize.
       (let [before s.table-width]
         (when (and (vim.api.nvim_buf_is_loaded s.buf) (visible? s.buf)
                    (not= before (table-width s)))
           (later s #(modify s #(do (reflow-tables s)
                                    (refit-images s))))))))

(fn diagram-at [s row]
  ;; The first row of the drawn diagram's block that row (0-based) is in, or nil.
  (accumulate [found nil _ d (ipairs (or s.diagrams [])) &until found]
    (when d.drawn
      (let [[after] (vim.api.nvim_buf_get_extmark_by_id s.buf diagram-ns d.mark {})]
        (when (and after (< row after) (>= row (- after d.height)))
          (- after d.height))))))

(fn fold [lnum]
  ;; The chat's 'foldexpr': thinking (">> " lines), and drawn diagrams' source.
  (let [buf (vim.api.nvim_get_current_buf)
        s (. chats buf)
        row (- lnum 1)
        top (when s (diagram-at s row))]
    (if (vim.startswith (vim.fn.getline lnum) ">>") 1
        (= top row) ">1"
        top 1
        0)))

;; UI rows --------------------------------------------------------------------------
;; The tool, permission and other "> kind: " rows keep their text, which the log and
;; <CR> rely on, but show quieter: the label gives way to an icon, a finished tool
;; loses its "— done", and an answered permission shows only its answer under the
;; tool. The cursor's line shows the text in full.

(local ui-ns (vim.api.nvim_create_namespace "acp-ui"))

;; A tool's icon by its ACP kind, from the Nerd Font symbols (kitty has them as a
;; fallback whatever the font). vim.g.acp-tool-icons, kind to icon, changes any.
(local tool-icons
  {:read 0xF06E      ; eye
   :edit 0xF040      ; pencil
   :delete 0xF1F8    ; bin
   :move 0xF0EC      ; arrows
   :search 0xF002    ; magnifier
   :execute 0xF120   ; terminal
   :think 0xF0EB     ; light bulb
   :fetch 0xF0AC     ; globe
   :switch_mode 0xF0E7 ; bolt
   :other 0xF0AD})   ; spanner

(fn tool-icon [kind]
  (or (?. vim.g.acp-tool-icons kind)
      (vim.fn.nr2char (or (. tool-icons kind) tool-icons.other))))

(fn ui-look [line kind]
  ;; {: icon : hl :hide [from to]... :marks [[from to group]]...} for a UI row, or nil.
  ;; Ranges are 0-based bytes, end exclusive. kind is a tool's ACP kind.
  (let [label (line:match "^> (%a+): ")
        start (when label (+ (length label) 4))
        (body-end status) (line:match "()%s—%s([^—]-)$")]
    (case label
      ;; The icon's colour is the status, so only "failed" is still said, and a diff's
      ;; counts lose their brackets for a colour each.
      :tool (let [(open added removed close) (line:match "() %(%+(%d+) %-(%d+)()%)%s—")
                  ;; open and close are 1-based: of the space before "(", and of ")".
                  ;; From the "(" on, 0-based: "(+4 -12)".
                  stats (when open
                          (let [paren open
                                plus (+ paren 1)
                                minus (+ plus 1 (length added) 1)]
                            {:hide [[paren (+ paren 1)] [(- close 1) close]]
                             :marks [[plus (+ plus 1 (length added)) :AcpDiffAdded]
                                     [minus (+ minus 1 (length removed)) :AcpDiffRemoved]]}))
                  hide (vim.list_extend [[0 start]]
                                        (vim.list_extend (if (and body-end (not= status "failed"))
                                                           [[(- body-end 1) (length line)]]
                                                           [])
                                                         (or (?. stats :hide) [])))]
              ;; Two spaces: kitty draws Nerd Font icons a little over one cell wide.
              {:icon (.. (tool-icon kind) "  ")
               :hl (case status
                     "done" :AcpToolDone
                     "failed" :AcpToolFailed
                     _ :AcpToolRunning)
               : hide
               ;; The row is muted, but a failure is said in full colour.
               :marks (vim.list_extend (if (and body-end (= status "failed"))
                                         [[(- body-end 1) (length line) :AcpToolFailed]]
                                         [])
                                       (or (?. stats :marks) []))})
      :permission (if (and status (not (vim.startswith status "awaiting")))
                    {:icon "   ↳ " :hl :AcpUiPrefix
                     :hide [[0 (+ (- body-end 1) (length " — "))]]}
                    {:icon "? " :hl :AcpAttention :hide [[0 start]]})
      ;; Waiting on you until answered, then the answer's colour.
      :elicitation {:icon "? "
                    :hl (if (and status (vim.startswith status "awaiting")) :AcpAttention :AcpUiPrefix)
                    :hide [[0 start]]}
      ;; An egress you allowed has the whole line in green: a way out of the sandbox.
      :egress (let [allowed? (and status (vim.startswith status "allowed"))]
                {:icon "⇄ "
                 :hl (if allowed? :AcpToolDone
                         (and status (vim.startswith status "refused")) :AcpToolFailed
                         :AcpAttention)
                 :line (when allowed? :AcpEgressAllowed)
                 :hide [[0 start]]})
      ;; Only an unusual end is in the chat, see session.end-turn.
      :stop {:icon "■ " :hl :AcpToolFailed :hide [[0 start]]}
      ;; The line under a reply: agent · model · time · speed, the agent in its colour.
      :turn (let [name-end (or (line:find " · " start true) (+ (length line) 1))]
              {:icon "" :hl :AcpUiPrefix
               :hide [[0 start]]
               :marks [[start (- name-end 1) :AcpTurnAgent]]})
      :acp {:icon "· " :hl :AcpUiPrefix :hide [[0 start]]})))

(fn decorate [buf row kind]
  ;; Restyles the UI row at row (0-based), after it's written or rewritten.
  (vim.api.nvim_buf_clear_namespace buf ui-ns row (+ row 1))
  (let [look (ui-look (line-at buf row) kind)]
    (when look
      (each [_ [from to] (ipairs look.hide)]
        (vim.api.nvim_buf_set_extmark buf ui-ns row from {:end_col to :conceal ""}))
      (each [_ [from to group] (ipairs (or look.marks []))]
        (vim.api.nvim_buf_set_extmark buf ui-ns row from {:end_col to :hl_group group :priority 200}))
      (when look.line
        (vim.api.nvim_buf_set_extmark buf ui-ns row 0 {:line_hl_group look.line :priority 50}))
      ;; Combined, so a line's background goes behind the icon too.
      (when (not= look.icon "")
        (vim.api.nvim_buf_set_extmark buf ui-ns row 0
                                      {:virt_text [[look.icon look.hl]]
                                       :virt_text_pos :inline
                                       :hl_mode :combine})))))

(fn joins-previous? [line]
  ;; Quoted lines stack directly under headings and other quoted lines (not thinking).
  (or (= line nil) (= line "") (line:match "^>[^>]") (line:match "^#")))

(fn put-line [s line kind]
  ;; Puts a standalone line at the end of the transcript, keeping an empty line after
  ;; it for what comes next. Returns the 0-based row it landed on. kind is a tool's.
  (align-table-above s (last-row s))
  (let [row (last-row s)
        previous (when (> row 0) (line-at s.buf (- row 1)))]
    (if (not= (last-line s) "")
      (append-after s ["" line ""])
      (joins-previous? previous)
      (replace-last s [line ""])
      (replace-last s ["" line ""])))
  (let [row (- (last-row s) 1)]
    (decorate s.buf row kind)
    row))

(fn status [s message]
  (later s (fn [] (modify s #(put-line s (.. "> acp: " message))))))

(fn begin-turn [s turn]
  ;; Files may have come or gone since the names were looked up.
  (set s.paths nil)
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
                                             (vim.split text "\n" {:plain true}))
                  ;; Every line before the one being written is complete, and one
                  ;; chunk can finish a table and carry on past it.
                  (for [r row (- (last-row s) 1)]
                    (when (not (table-row? (line-at s.buf (+ r 1))))
                      (align-table-above s r))
                    (draw-diagram s r)
                    (show-images s r)
                    (rule-heading s r)))))))

(fn add-line [s block]
  (later s #(modify s
              (fn []
                (let [row (put-line s block.line block.kind)]
                  (set block.mark (vim.api.nvim_buf_set_extmark s.buf ns row 0 {:right_gravity false})))))))

(fn update-line [s block]
  ;; Checked when it runs: a held add-line has no mark yet. A tool that finished may
  ;; have made or removed files the chat names.
  (set s.paths nil)
  (later s #(when block.mark
              (modify s
                (fn []
                  (let [[row] (vim.api.nvim_buf_get_extmark_by_id s.buf ns block.mark {})]
                    (when row
                      (let [current (. (vim.api.nvim_buf_get_lines s.buf row (+ row 1) false) 1)]
                        (vim.api.nvim_buf_set_text s.buf row 0 row (length current) [block.line])
                        (decorate s.buf row block.kind)))))))))

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

;; Choices ----------------------------------------------------------------------------
;; The choices of a permission, egress request or question are lines "  N. name"
;; attached under it, picked with <CR> on one; the number is hidden as the line is
;; drawn. The one the cursor is on shows as selected: ▸ in its indent, then its name
;; as a pill of the accent colour. A mark, not drawn-time decoration, as moving the
;; cursor alone doesn't redraw lines.

(local selection-ns (vim.api.nvim_create_namespace "acp-selection"))

(set show-selection
     (fn [s]
       (when (vim.api.nvim_buf_is_loaded s.buf)
         (vim.api.nvim_buf_clear_namespace s.buf selection-ns 0 -1)
         (when (= (vim.api.nvim_get_current_buf) s.buf)
           (let [row (- (. (vim.api.nvim_win_get_cursor 0) 1) 1)
                 line (line-at s.buf row)
                 (number name) (line:match "^  (%d+%. )()")]
             (when (and number (. (attached-rows s) row))
               ;; Drawn over the whole line, as the cursor's line shows what's concealed
               ;; (its number): ▸ in the indent, the name as a pill, then spaces over
               ;; what's left, so its name lines up with the other choices'.
               (let [label (line:sub name)
                     pill (.. " " label " ")
                     width (vim.fn.strdisplaywidth line)
                     used (+ 1 (vim.fn.strdisplaywidth pill))]
                 (vim.api.nvim_buf_set_extmark s.buf selection-ns row 0
                                               {:virt_text [["▸" :AcpChoiceArrow]
                                                            [pill :AcpChoiceSelected]
                                                            [(string.rep " " (math.max 0 (- width used))) :Normal]]
                                                :virt_text_pos :overlay :priority 300}))))))))

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
              (if (>= row (+ input 1)) :input
                  (>= row input) nil
                  (= section :you) (if (= line "") :you-blank :you)
                  (not= section :agent) nil
                  (or (vim.startswith line ">") (. attached row)) nil
                  (= line "") :blank
                  ;; The turn's own hidden ## Agent line, shaded only with text after it.
                  (= heading :agent) :turn
                  ;; The agent's # and ## headings, which open a block of their own.
                  (line:match "^ ? ? ?##? ") :section
                  :agent))))
    ;; A blank line takes the agent's shade only inside its text, not around UI rows,
    ;; and not before a # or ## heading: the gap there ends the block above, and the
    ;; heading starts one with its rule and its text.
    ;; The hidden ## Agent line is shaded only when text follows it (past blank lines):
    ;; a reply that starts with a tool call would otherwise open with an empty block.
    (let [result {}
          text? (fn [kind] (or (= kind :agent) (= kind :section)))
          next-kind (fn [row]
                      (var after (+ row 1))
                      (while (= (. kinds after) :blank) (set after (+ after 1)))
                      (. kinds after))]
      (for [row top bot]
        (let [kind (. kinds row)]
          (if (= kind :turn)
            (when (text? (next-kind row))
              (tset result row :AcpAgent))
            (= kind :blank)
            (do
              (var before (- row 1))
              (while (= (. kinds before) :blank) (set before (- before 1)))
              (when (and (= (next-kind row) :agent)
                         (or (text? (. kinds before))
                             ;; Under a ## Agent line that has text after it.
                             (= (. kinds before) :turn)
                             (and (< before top) (= start-section :agent))))
                (tset result row :AcpAgent)))
            ;; A blank line in a prompt you sent is shaded only between its
            ;; paragraphs, so the gap after the prompt is plain.
            (= kind :you-blank)
            (do
              (var after (+ row 1))
              (while (= (. kinds after) :you-blank) (set after (+ after 1)))
              (when (= (. kinds after) :you)
                (tset result row :AcpYou)))
            (= kind :you) (tset result row :AcpYou)
            ;; The prompt you're writing, apart from the ones already sent.
            (= kind :input) (tset result row :AcpInput)
            (text? kind) (tset result row :AcpAgent))))
      result)))

(fn gutter []
  ;; The chat's 'statuscolumn': a bar beside your prompts and the agent's replies, on
  ;; every screen row of them, wrapped ones too, from the shades worked out for this
  ;; redraw. A virtual line (a block's padding, a heading's rule, a drawing, an image)
  ;; is counted as the line it hangs from, so it has that line's bar.
  (let [buf (vim.api.nvim_win_get_buf vim.g.statusline_winid)
        group (?. drawing buf (- vim.v.lnum 1))]
    ;; Three columns: the bar, then two of padding in the block's own shade, so its
    ;; text sits inside the block rather than against its edge.
    (case group
      :AcpYou "%#AcpYouBar#▎%#AcpYou#  "
      :AcpInput "%#AcpInputBar#▎%#AcpInput#  "
      :AcpAgent "%#AcpAgentBar#▎%#AcpAgent#  "
      _ "   ")))

;; File names ------------------------------------------------------------------------
;; A word naming a file or directory that's there, under the session's directory or as
;; an absolute or ~ path, shows as AcpPath (bold, underlined), with any :line after it.
;; Looked up as lines are drawn, and remembered per chat, as a reply names the same
;; files over and over.

(fn path-exists? [s path]
  (let [known (or s.paths (do (set s.paths {}) s.paths))]
    (when (= nil (. known path))
      (let [full (if (or (vim.startswith path "/") (vim.startswith path "~"))
                   (vim.fn.expand path)
                   (.. (or (?. s :session :cwd) (vim.fn.getcwd)) "/" path))]
        (tset known path (not= nil (vim.uv.fs_stat full)))))
    (. known path)))

(fn path-ranges [s line]
  ;; [from to] byte ranges (0-based, end exclusive) of the file names in line. Only
  ;; words that look like paths: with a / or a file extension.
  (let [ranges []]
    (each [from word to (line:gmatch "()([%w_%.%-/~]+)()")]
      (let [name (word:gsub "[%.]+$" "")
            line-ref (: (line:sub to) :match "^:%d+")]
        (when (and (or (name:find "/" 1 true) (name:match "%.%a%w*$"))
                   (> (length name) 2)
                   (not (name:match "^%.+$"))
                   (path-exists? s name))
          (table.insert ranges [(- from 1) (+ (- from 1) (length name)
                                              (if (and line-ref (= name word)) (length line-ref) 0))]))))
    ranges))

;; Block padding ----------------------------------------------------------------------
;; A row of a block's own shade above and below it, so its text isn't tight against
;; its top and bottom edges. The buffer's one blank line between blocks stays the plain
;; gap, so the padding is virtual lines, worked out from the shades as the chat is
;; drawn: when the blocks' edges on screen change, the padding there is put again,
;; after the redraw, as a redraw can't change marks.

(local pad-ns (vim.api.nvim_create_namespace "acp-pad"))

(fn block-edges [buf shaded top bot]
  ;; [row above? group] for each edge of a shaded block in rows top..bot. A block that
  ;; starts with its turn's hidden ## You or ## Agent line has an empty row of the
  ;; shade there already, so it gets no padding above.
  (let [edges []]
    (for [row top bot]
      (let [group (. shaded row)]
        (when group
          (when (and (not= group (. shaded (- row 1)))
                     (let [line (line-at buf row)]
                       (not (or (vim.startswith line "## You") (vim.startswith line "## Agent")))))
            (table.insert edges [row true group]))
          ;; Not under the input: it ends the buffer, and Neovim doesn't scroll virtual
          ;; lines under the last line into view, so they'd come and go as you type.
          (when (and (not= group (. shaded (+ row 1))) (not= group :AcpInput))
            (table.insert edges [row false group])))))
    edges))

(fn git-branch [s]
  ;; The branch checked out in the session's directory, or nil. Asked of git in the
  ;; background and kept a few seconds, as it's wanted on every redraw; a change
  ;; redraws the chat.
  (let [now (os.time)
        cwd (?. s :session :cwd)]
    (when (and cwd (not s.branch-asking) (> (- now (or s.branch-at 0)) 5))
      (set s.branch-asking true)
      (pcall vim.system ["git" "-C" cwd "branch" "--show-current"] {:text true}
             (vim.schedule_wrap
               (fn [result]
                 (let [branch (vim.trim (or result.stdout ""))
                       branch (when (and (= result.code 0) (not= branch "")) branch)]
                   (set s.branch-asking false)
                   (set s.branch-at (os.time))
                   (when (not= branch s.branch)
                     (set s.branch branch)
                     (when (vim.api.nvim_buf_is_loaded s.buf)
                       (pcall vim.api.nvim__redraw {:buf s.buf :valid false}))))))))
    s.branch))

(fn input-footer [s]
  ;; The agent, its model and the git branch, as chunks, for the input's top row.
  (let [model (accumulate [found nil _ o (ipairs (or s.config [])) &until found]
                (when (= o.category :model) o.display))
        name (or s.label (?. s :agent :name) "agent")
        branch (git-branch s)]
    (-> [[name [:AcpInput :AcpTurnAgent]]]
        (vim.list_extend (if model [[(.. " · " model) [:AcpInput :AcpUiPrefix]]] []))
        ;; The branch icon, from the Nerd Font symbols, as the tools' are.
        (vim.list_extend (if branch
                           [[(.. " · " (vim.fn.nr2char 0xE0A0) " " branch) [:AcpInput :AcpUiPrefix]]]
                           [])))))

(fn pad-lines [s above? group width]
  ;; A block's padding: a row of its shade.
  [[[(string.rep " " width) group]]])

(fn pad-blocks [s top bot shaded]
  (let [edges (block-edges s.buf shaded top bot)
        width (or (table-width s) 80)
        key (.. (table.concat (icollect [_ [row above? group] (ipairs edges)]
                                (.. row (if above? "^" "v") group))
                              " ")
                width)]
    (when (not= key s.pad-key)
      (set s.pad-key key)
      (vim.schedule
        (fn []
          (when (vim.api.nvim_buf_is_loaded s.buf)
            (let [last (- (line-count s.buf) 1)]
              (vim.api.nvim_buf_clear_namespace s.buf pad-ns (math.max 0 (- top 1)) (+ bot 2))
              (each [_ [row above? group] (ipairs edges)]
                (when (<= row last)
                  (vim.api.nvim_buf_set_extmark s.buf pad-ns row 0
                                                {:virt_lines (pad-lines s above? group width)
                                                 :virt_lines_above above?}))))))))))

;; Whole-line shades -------------------------------------------------------------------
;; Concealed markers still count where 'linebreak' wraps a line, so a wrapped row can end
;; a few cells short of the window, cells that aren't text and that a highlight of the
;; text doesn't reach. A whole-line highlight, as 'cursorline' is, does, but only from a
;; mark, not one put while drawing: so, like the padding, marks for the rows around the
;; view, put after a redraw whenever the shades there change.

(local line-ns (vim.api.nvim_create_namespace "acp-line-shade"))

(fn sync-line-shades [s from to shaded]
  (let [key (table.concat (fcollect [row from to] (or (. shaded row) "-")) " ")]
    (when (or (not= key s.line-key) (not= from s.line-from))
      (set s.line-key key)
      (set s.line-from from)
      (vim.schedule
        (fn []
          (when (vim.api.nvim_buf_is_loaded s.buf)
            (let [last (- (line-count s.buf) 1)]
              (vim.api.nvim_buf_clear_namespace s.buf line-ns from (+ to 1))
              (for [row from (math.min to last)]
                (let [group (. shaded row)]
                  (when group
                    (vim.api.nvim_buf_set_extmark s.buf line-ns row 0
                                                  {:line_hl_group group :priority 1})))))))))))

(vim.api.nvim_set_decoration_provider shade-ns
  {:on_win (fn [_ win buf top]
             (let [s (. chats buf)]
               (if (and s (vim.api.nvim_buf_is_loaded buf))
                 ;; Rows by count from the top, a window's height and a margin, rather than
                 ;; the last row on screen: the padding takes rows of the screen, so with
                 ;; it worked out from the last row, putting it moved the last row, which
                 ;; changed the padding, which moved it back, and the window flickered.
                 (let [from (math.max 0 (- top lookahead))
                       to (+ top (vim.api.nvim_win_get_height win) lookahead)
                       shaded (shades s (math.max 0 (- from 1)) (+ to 1))]
                   (tset drawing buf shaded)
                   (tset drawing-attached buf (attached-rows s))
                   (pad-blocks s from to shaded)
                   (sync-line-shades s from to shaded)
                   true)
                 false)))
   :on_line (fn [_ _ buf row]
              (let [group (?. drawing buf row)
                    s (. chats buf)]
                ;; Its text and on to the window's edge, at once; the cells a wrapped
                ;; row leaves where its concealed markers would have been are filled by
                ;; the line marks put after the redraw, see sync-line-shades.
                (when group
                  (vim.api.nvim_buf_set_extmark buf shade-ns row 0
                                                {:end_row (+ row 1) :end_col 0 :hl_group group
                                                 :hl_eol true :ephemeral true :priority 1}))
                (when s
                  (let [line (line-at buf row)
                        ;; In a tool, note or thinking row, as quiet as the row.
                        path-group (if (vim.startswith line ">") :AcpPathQuiet :AcpPath)]
                    (each [_ [from to] (ipairs (path-ranges s line))]
                      (vim.api.nvim_buf_set_extmark buf shade-ns row from
                                                    {:end_col to :hl_group path-group
                                                     :ephemeral true :priority 200}))
                    ;; A prompt's hidden ## You line keeps its time, at the right.
                    (let [time (line:match "^## You — (%d+:%d+)")]
                      (when time
                        (vim.api.nvim_buf_set_extmark buf shade-ns row 0
                                                      {:virt_text [[time :AcpTurn]]
                                                       :virt_text_pos :right_align
                                                       :hl_mode :combine
                                                       :ephemeral true})))
                    ;; The input's hidden ## You line: the agent, its model and the git
                    ;; branch, at the right. On its top row, not under it, as the input
                    ;; ends the buffer and lines under the last aren't scrolled into view.
                    (when (= row (+ (input-start s) 1))
                      (vim.api.nvim_buf_set_extmark buf shade-ns row 0
                                                    {:virt_text (input-footer s)
                                                     :virt_text_pos :right_align
                                                     :hl_mode :combine
                                                     :ephemeral true}))
                    ;; A choice's number is hidden: the selected one is shown, see
                    ;; Choices, and a choice is picked by its row, not its number.
                    (let [number (when (?. drawing-attached buf row) (line:match "^  %d+%. "))]
                      (when number
                        (vim.api.nvim_buf_set_extmark buf shade-ns row 2
                                                      {:end_col (length number) :conceal ""
                                                       :ephemeral true})))))))})

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
 : fold
 : gutter
 : open-code-block}
