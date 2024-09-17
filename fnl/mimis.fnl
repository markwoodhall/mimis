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

(fn leader-map [mode map action options]
  (vim.keymap.set 
    mode 
    (.. nvim.g.mapleader map)
    action 
    options))

{: bottom-pane
 : first
 : second
 : split 
 : exists?
 : leader-map}
