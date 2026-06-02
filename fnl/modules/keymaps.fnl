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

  (vim.api.nvim_create_user_command
    "Recent"
    (fn [_]
      (vim.fn.setloclist 0 vim.g.recent_files)
      (vim.cmd "lopen"))
    {:bang false :desc "Recent files" })

  (vim.api.nvim_create_autocmd
    "QuickFixCmdPost" 
    {:pattern [:grep :vimgrep] :command :copen})

  (let [cg (vim.api.nvim_create_augroup "mimis-recentf" {:clear true})]
    (vim.api.nvim_create_autocmd 
      "BufRead" 
      {:pattern "*"
       :group cg
       :desc "Setup recent files"
       :callback 
       (fn []
         (let [current-file (vim.fn.expand "%:p")]
           (when (mimis.exists? current-file)
             (let [old (icollect [_ v (ipairs vim.v.oldfiles)]
                         (when (mimis.exists? (vim.fn.expand v))
                           {:filename v :lnum 1 :text "Last opened: Previous session"}))
                   fresh {:filename current-file :lnum 1 :text (.. "Last opened: " (os.date))}
                   all (mimis.concat (mimis.concat [fresh] (or vim.g.recent_files [])) old)
                   seen {}]
               (set vim.g.recent_files
                    (icollect [_ e (ipairs all)]
                      (when (and e.filename (not (. seen e.filename)))
                        (tset seen e.filename true)
                        e)))))))})

    (vim.api.nvim_create_autocmd 
      "VimEnter" 
      {:group cg
       :desc "Setup recent files"
       :callback 
       (fn []
         (set vim.g.recent_files (icollect [_ v (ipairs vim.v.oldfiles)]
                                   (when (mimis.exists? (vim.fn.expand v))
                                     {:filename v :lnum 1 :text "Last Opened: Previous session"}))))}))

  (vim.keymap.set "n" "<Esc><Esc>" "<c-\\><c-n>:q<CR>")

  ;; terminal mappings
  (vim.keymap.set "t" "<Esc>" "<c-\\><c-n>")
  (vim.keymap.set "t" "<Esc><Esc>" "<c-\\><c-n>:q<CR>")

  (var persistent-terminal nil)
  (vim.api.nvim_create_user_command
    "Terminal" 
    (fn [] 
      (if (and persistent-terminal
               (> (vim.fn.bufexists persistent-terminal) 0))
        (mimis.bottom-pane-buff persistent-terminal)
        (set persistent-terminal (mimis.bottom-pane-shell nvim.o.shell))))
    {:bang false :desc "Toggle terminal" }))

{: enable
 : setup }
