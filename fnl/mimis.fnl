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
  (vim.cmd "setlocal norelativenumber")
  (vim.cmd "setlocal nonumber")
  (vim.cmd "setlocal nolist")
  (vim.cmd "setlocal filetype=off")
  (vim.cmd "setlocal syntax=off"))

(fn bottom-pane-buff [bufnum]
  (vim.cmd "wincmd n")
  (vim.cmd "wincmd J")
  (vim.cmd "15wincmd_")
  (vim.cmd (.. "buffer " bufnum)))

(fn split [s pattern]
  (if s
    (nvim.fn.split s pattern "g")
    []))

(fn first [c]
  (?. c 1))

(fn second [c]
  (?. c 2))

(fn take [c i]
  (table.move c 1 i 1 []))

(fn last [c]
  (?. c (length c)))

(fn but-last [c]
  (take c (- (length c) 1)))

(fn nth [c n]
  (?. c n))

(fn empty [c]
  (= (length c) 0))

(fn distinct [c]
  (if c
    (accumulate 
      [t [] _ v (ipairs c)]
      (do 
        (when (empty (icollect [_ e (ipairs t)]
                            (if (= e v)
                              v)))
          (table.insert t v))
        t))))

(fn concat [t1 t2]
  (if (and t1 t2)
    (do (for [i 1 (length t2)]
          (tset t1 (+ (length t1) 1) (. t2 i)))
      t1)
    (if (not t2)
      t1
      (if (not t1)
        t2))))	

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

(fn glob [path]
  (nvim.fn.glob path true true true))

(fn globpath [path expression]
  (nvim.fn.globpath path expression true true true))

(fn join [c separator]
  (nvim.fn.join c separator))

(fn pad-string [s n]
  (var x "")
  (for [_ 1 n]
    (set x (.. x s)))
  x)

(fn ->environment-variables [env]
  (let [lines (split env "\n")
        lines (icollect [_ l (ipairs lines)]
                (if (not (string.find l "^#"))
                  l))
        vars (join lines " ")
        no-exp-vars (join (split vars "EXPORT ") "")
        no-exp-vars (join (split no-exp-vars "export ") "")]
    no-exp-vars))

{: bottom-pane
 : bottom-pane-buff
 : bottom-pane-shell
 : first
 : second
 : last
 : take
 : but-last
 : nth
 : empty
 : distinct
 : concat
 : count-matches
 : add-match
 : split 
 : exists?
 : glob
 : globpath
 : pad-string
 : join
 : ->environment-variables
 : leader-map}
