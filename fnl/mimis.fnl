(fn pane
  [content listed scratch no-buffer split]
  (vim.cmd split)
  (let [buff (when (not no-buffer) (vim.api.nvim_create_buf listed scratch))]
    (if scratch
      (when (not= content "") 
        (vim.api.nvim_buf_set_lines
          0
          0 -1
          false
          (vim.fn.split content "\\n" "g")))
      (when (not= content "") (vim.cmd (.. "e " content))))
    (when (= "split" split)
      (vim.cmd "wincmd J")
      (vim.cmd "25wincmd_"))
    buff))

(fn bottom-pane
  [content listed scratch no-buffer]
  (pane content listed scratch no-buffer "split"))

(fn side-pane
  [content listed scratch no-buffer]
  (pane content listed scratch no-buffer "vsplit"))

(fn bottom-pane-shell [cmd]
  (let [buff (bottom-pane "" true true true)]
    (vim.cmd (.. "terminal " cmd))
    (vim.cmd "setlocal norelativenumber")
    (vim.cmd "setlocal nonumber")
    (vim.cmd "setlocal nolist")
    (vim.cmd "setlocal filetype=off")
    (vim.cmd "setlocal syntax=off")
    (or buff (vim.api.nvim_get_current_buf))))

(fn bottom-pane-buff [bufnum]
  (vim.cmd "split")
  (vim.cmd "wincmd J")
  (vim.cmd "25wincmd_")
  (vim.cmd (.. "buffer " bufnum)))

(fn split [s pattern]
  (if s
    (vim.fn.split s pattern "g")
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
  (= (vim.fn.filereadable path) 1))

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
    (.. vim.g.mapleader map)
    action 
    options))

(fn glob [path]
  (vim.fn.glob path true true true))

(fn globpath [path expression]
  (vim.fn.globpath path expression true true true))

(fn join [c separator]
  (vim.fn.join c separator))

(fn pad-string [s n]
  (var x "")
  (for [_ 1 n]
    (set x (.. x s)))
  x)

(fn try-add-runtimepath [path]
  (let [expanded (vim.fn.expand path)]
    (if (= (vim.fn.isdirectory expanded) 1)
      (set vim.o.runtimepath (.. vim.o.runtimepath "," path))
      (vim.notify (.. "mimis: runtimepath missing: " path)
                  vim.log.levels.WARN))))

(fn try-add-treesitter-path [grammar version]
  (try-add-runtimepath
    (.. "$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-"
        grammar "/" version)))

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
 : side-pane
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
 : try-add-runtimepath
 : try-add-treesitter-path
 : leader-map}
