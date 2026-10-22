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
  (tset (. vim.wo win) :conceallevel 0))

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
  (when (and s.buf (vim.api.nvim_buf_is_valid s.buf))
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
  (when (vim.api.nvim_buf_is_valid s.buf)
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
  ;; Quoted lines stack directly under headings and other quoted lines.
  (or (= line nil) (= line "") (line:match "^[>#]")))

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
 : prompt-text
 : clear-prompt
 : wipe
 : open-code-block}
