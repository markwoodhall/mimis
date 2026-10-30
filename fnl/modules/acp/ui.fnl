;; The pickers and prompts the ACP client asks through. Neovim's own vim.ui.select and
;; vim.ui.input draw in the command line, which 'cmdheight' 0 hides, so while they are
;; still Neovim's own these open floating windows instead. Anything else that replaced
;; them (a picker plugin, a test) is used as it is.

(fn stock? [f]
  (let [source (. (debug.getinfo f :S) :source)]
    (and source (not= nil (string.find source "vim/ui.lua" 1 true)))))

(fn one-line [text]
  (pick-values 1 (string.gsub (tostring text) "%s*\n%s*" " ")))

(fn wrap [text width]
  (let [lines []]
    (each [_ paragraph (ipairs (vim.split text "\n" {:plain true}))]
      (var line "")
      (each [word (string.gmatch paragraph "%S+")]
        (if (= line "")
          (set line word)
          (<= (vim.fn.strdisplaywidth (.. line " " word)) width)
          (set line (.. line " " word))
          (do (table.insert lines line)
              (set line word))))
      (table.insert lines line))
    lines))

(fn heading [prompt]
  ;; "strategy: " -> "strategy"
  (pick-values 1 (string.gsub (or prompt "") "[:%s]+$" "")))

(fn widest [lines]
  (accumulate [w 0 _ l (ipairs lines)]
    (math.max w (vim.fn.strdisplaywidth l))))

(fn float [buf lines width footer enter?]
  ;; A window around buf, centered, as tall as lines need once wrapped.
  (let [height (math.min (- vim.o.lines 6)
                         (accumulate [h 0 _ l (ipairs lines)]
                           (+ h (math.max 1 (math.ceil (/ (vim.fn.strdisplaywidth l) width))))))
        win (vim.api.nvim_open_win buf enter?
              {:relative :editor
               : width
               : height
               :row (math.max 0 (- (math.floor (/ (- vim.o.lines height) 2)) 1))
               :col (math.floor (/ (- vim.o.columns width) 2))
               :style :minimal
               :border :rounded
               :title " ACP "
               :title_pos :center
               : footer
               :footer_pos :center})]
    (tset vim.wo win :wrap true)
    (tset vim.wo win :linebreak true)
    win))

(fn width-for [lines]
  (math.min (math.min 100 (- vim.o.columns 6))
            (math.max 40 (+ 2 (widest lines)))))

(fn closing [win on-done]
  ;; A function that finishes once: closes win and hands the result on, later.
  (var done? false)
  (fn [...]
    (when (not done?)
      (set done? true)
      (let [args [...]
            n (_G.select :# ...)]
        (when (vim.api.nvim_win_is_valid win)
          (pcall vim.api.nvim_win_close win true))
        (vim.schedule #(on-done (unpack args 1 n)))))))

(fn float-select [items opts on-choice]
  (let [format (or opts.format_item tostring)
        labels (icollect [i item (ipairs items)]
                 (.. i ". " (one-line (format item))))
        width (width-for (vim.list_extend (vim.list_slice labels) [(heading opts.prompt)]))
        header (wrap (heading opts.prompt) width)
        first-row (+ (length header) 2)
        lines (vim.list_extend (vim.list_extend (vim.list_slice header) [""]) labels)
        buf (vim.api.nvim_create_buf false true)]
    (vim.api.nvim_buf_set_lines buf 0 -1 false lines)
    (tset vim.bo buf :bufhidden :wipe)
    (let [win (float buf lines width " <CR> choose · 1-9 jump · q cancel " true)
          finish (closing win on-choice)
          last-row (length lines)
          pick (fn [i] (finish (. items i) i))]
      (vim.api.nvim_win_set_cursor
        win [(math.min (+ first-row (- (math.max 1 (or opts.cursor 1)) 1)) last-row) 0])
      (tset vim.wo win :cursorline true)
      (vim.api.nvim_create_autocmd :CursorMoved
        {:buffer buf
         :callback #(let [row (. (vim.api.nvim_win_get_cursor win) 1)]
                      (when (or (< row first-row) (> row last-row))
                        (vim.api.nvim_win_set_cursor
                          win [(math.max first-row (math.min row last-row)) 0])))})
      (vim.api.nvim_create_autocmd :BufLeave {:buffer buf :once true :callback #(finish nil)})
      (vim.keymap.set :n "<CR>"
                      #(let [i (- (. (vim.api.nvim_win_get_cursor win) 1) (- first-row 1))]
                         (pick i))
                      {:buffer buf :nowait true})
      (for [i 1 (math.min 9 (length items))]
        (vim.keymap.set :n (tostring i) #(pick i) {:buffer buf :nowait true}))
      (each [_ key (ipairs ["q" "<Esc>" "<C-c>"])]
        (vim.keymap.set :n key #(finish nil) {:buffer buf :nowait true})))))

(fn float-input [opts on-confirm]
  (let [width (width-for [(heading opts.prompt)])
        header (wrap (heading opts.prompt) width)
        buf (vim.api.nvim_create_buf false true)
        text (one-line (or opts.default ""))
        lines (vim.list_extend (vim.list_slice header) ["" (.. "> " text)])]
    (tset vim.bo buf :bufhidden :wipe)
    (tset vim.bo buf :buftype :prompt)
    (vim.fn.prompt_setprompt buf "> ")
    (vim.api.nvim_buf_set_lines buf 0 -1 false lines)
    (let [win (float buf lines width " <CR> accept · <C-c> cancel " true)
          finish (closing win on-confirm)]
      ;; The text handed over may start above the header, so take the last line only.
      (vim.fn.prompt_setcallback buf
        (fn [answer]
          (let [rows (vim.split answer "\n" {:plain true})
                last (. rows (length rows))]
            (finish (if (vim.startswith last "> ") (string.sub last 3) last)))))
      (vim.api.nvim_create_autocmd :BufLeave {:buffer buf :once true :callback #(finish nil)})
      (vim.keymap.set [:i :n] "<C-c>" #(do (vim.cmd :stopinsert) (finish nil)) {:buffer buf})
      (vim.keymap.set :n "q" #(finish nil) {:buffer buf :nowait true})
      (vim.keymap.set :n "<Esc>" #(finish nil) {:buffer buf :nowait true})
      (vim.api.nvim_win_set_cursor win [(length lines) (length (. lines (length lines)))])
      (vim.cmd "startinsert!"))))

(fn select [items opts on-choice]
  (if (stock? vim.ui.select)
    (float-select items opts on-choice)
    (vim.ui.select items opts on-choice)))

(fn input [opts on-confirm]
  (if (stock? vim.ui.input)
    (float-input opts on-confirm)
    (vim.ui.input opts on-confirm)))

{: select
 : input}
