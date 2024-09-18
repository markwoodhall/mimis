(local nvim (require :nvim))

(fn bottom-pane
  [filetype content listed scratch]
  (vim.cmd "wincmd n")
  (let [_ (vim.api.nvim_create_buf listed scratch)]
    (set nvim.bo.filetype filetype)
    (when (or (= filetype "markdown")
              (= filetype "org"))
      (vim.cmd "setlocal wrap"))
    (if scratch
      (when (not= content "") 
        (vim.api.nvim_buf_set_lines
          0
          0 -1
          false
          (nvim.fn.split content "\\n" "g")))
      (when (not= content "") (vim.cmd (.. "e " content))))
    (vim.cmd "wincmd J")
    (vim.cmd "15wincmd_")))

(fn bottom-pane-shell [cmd]
  (bottom-pane "" "" true true)
  (vim.fn.termopen cmd)
  (nvim.ex.setlocal :norelativenumber)
  (nvim.ex.setlocal :nonumber)
  (nvim.ex.setlocal :nowrap)
  (set nvim.b.filetype :off)
  (set nvim.b.syntax :off))

(fn split [s pattern]
  (if s
    (nvim.fn.split s pattern "g")
    []))

(fn first [c]
  (?. c 1))

(fn second [c]
  (?. c 2))

(fn exists? [path]
  (= (nvim.fn.filereadable path) 1))

(fn count-matches [s pattern]
  (var c 0)
  (each [_ (string.gmatch s pattern)]
    (set c (+ 1 c)))
  c)

(fn add-match [s matchs col]
  (if (or (and matchs
               (> (count-matches s matchs) 0))
          (not matchs))
    [s (unpack col)]
    col))

(fn leader-map [mode map action options]
  (vim.keymap.set 
    mode 
    (.. nvim.g.mapleader map)
    action 
    options))

{: bottom-pane
 : bottom-pane-shell
 : first
 : second
 : count-matches
 : add-match
 : split 
 : exists?
 : leader-map}
