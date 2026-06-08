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
       (vim.keymap.set "n" ">)"
         (fn [] (string.rep "ylr w%p" vim.v.count1))
         {:buf 0 :expr true})

       (vim.keymap.set "n" "<r" "y%[(d%\"0P=%" {:buf 0})

       (vim.keymap.set "i" "(" "()<left>" {:buf 0})
       (vim.keymap.set "i" ")" "<right>" {:buf 0})

       (vim.keymap.set "i" "[" "[]<left>" {:buf 0})
       (vim.keymap.set "i" "]" "<right>" {:buf 0})

       (vim.keymap.set "i" "{" "{}<left>" {:buf 0})
       (vim.keymap.set "i" "}" "<right>" {:buf 0}))}))

{: enable
 : setup }

