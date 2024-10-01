(local nvim (require "nvim"))
(local mimis (require :mimis))

(fn enable [])

(fn setup []
  (vim.api.nvim_create_user_command
    "Buffers"
    (fn [_]
      (let [bufnrs (vim.fn.range 1 (vim.fn.bufnr "$"))
            bufnames (icollect [_ v (ipairs bufnrs)]
                       (when (not= (vim.fn.buflisted v) 0) 
                         (let [name (vim.fn.bufname v)]
                           (when (not= name "")
                             {:filename name
                              :lnum 1
                              :text v}))))]
        (vim.fn.setloclist 0 bufnames)
        (vim.cmd "lopen")))
    {:bang false :desc "buffer wrapper" :nargs "*"
     :complete (fn [])})

  ;; buffers
  (mimis.leader-map "n" "ba" ":e #<CR>" {:desc "toggle-buffers"})
  (mimis.leader-map "n" "bh" ":nohl<CR>" {:desc "no-highlight-search"})
  (mimis.leader-map "n" "bn" ":bn<CR>" {:desc "goto-next-buffer"})
  (mimis.leader-map "n" "bp" ":bp<CR>" {:desc "goto-previous-buffer"})
  (mimis.leader-map "n" "bx" ":close<CR>" {:desc "close-buffer"})
  (mimis.leader-map "n" "bX" ":bd!<CR>" {:desc "delete-buffer"})

  ;; window mappings
  (mimis.leader-map "n" "ws" "<c-w>v<c-w>w" {:desc "split-window-vertically"})
  (mimis.leader-map "n" "wS" "<c-w>s" {:desc "split-window-horizontally"})
  (mimis.leader-map "n" "wh" "<c-w>h" {:desc "move-to-right-window"})
  (mimis.leader-map "n" "wj" "<c-w>j" {:desc "Move-to-below-window"})
  (mimis.leader-map "n" "wk" "<c-w>k" {:desc "Move-to-above-window"})
  (mimis.leader-map "n" "wl" "<c-w>l" {:desc "Move-to-left-window"})
  (mimis.leader-map "n" "wm" "<c-w>|<c-w>_" {:desc "maximize-window"})
  (mimis.leader-map "n" "wp" "<c-w>|<c-w>_|:15wincmd_<cr>" {:desc "window-to-bottom-pane"})
  (mimis.leader-map "n" "w=" "<c-w>=" {:desc "balance-windows"})
  (vim.keymap.set "n" "<Esc><Esc>" "<c-\\><c-n>:q<CR>")

  ;; terminal mappings
  (vim.keymap.set "t" "<Esc>" "<c-\\><c-n>")
  (vim.keymap.set "t" "<Esc><Esc>" "<c-\\><c-n>:q<CR>")

  (var persistent-terminal nil)
  (mimis.leader-map 
    "n" 
    "tt" 
    (fn [] 
      (if (and persistent-terminal
               (> (vim.fn.bufexists persistent-terminal) 0))
        (mimis.bottom-pane-buff persistent-terminal)
        (set persistent-terminal (- (mimis.bottom-pane-shell nvim.o.shell) 1))))
    {:desc "toggle-terminal"})

  (mimis.leader-map 
    "n" 
    "tn" 
    (partial mimis.bottom-pane-shell nvim.o.shell)
    {:desc "new-terminal"})

  ;; defaults
  (vim.keymap.set "n" "<j>" "<j><g>")
  (vim.keymap.set "n" "<k>" "<k><g>")
  (let [wk (require :which-key)] 
    (wk.add 
      [{1 (.. nvim.g.mapleader "t") :group "terminal"}
       {1 (.. nvim.g.mapleader "b") :group "buffers"}
       {1 (.. nvim.g.mapleader "f") :group "find"}
       {1 (.. nvim.g.mapleader "w") :group "window"}])))

{: enable
 : setup }
