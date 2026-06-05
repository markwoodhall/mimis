(local ft (require :modules.filetypes))
(local mimis (require :mimis))

(var paredit-languages [])

(fn enable [languages module-hook]
  (let [languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set paredit-languages (mimis.concat paredit-languages languages))))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern paredit-languages
     :group (vim.api.nvim_create_augroup "mimis-paredit" {:clear true})
     :desc "Setup paredit for specific filetypes"
     :callback 
     (fn []
       (vim.keymap.set "n" ">)" "xi <esc>w%p" {:buf 0})
       (vim.keymap.set "n" ">)" "x%P" {:buf 0})

       (vim.keymap.set "i" "(" "()<left>" {:buf 0})
       (vim.keymap.set "i" "[" "[]<left>" {:buf 0})
       (vim.keymap.set "i" "{" "{}<left>" {:buf 0})
       (vim.keymap.set "i" "\"" "\"\"<left>" {:buf 0}))}))

{: enable
 : setup }
