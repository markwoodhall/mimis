(local plugins (require :plugins))
(local ft (require :modules.filetypes))
(local mimis (require :mimis))

(var paredit-languages [])

(fn enable [languages module-hook]
  (let [languages (or languages 
                      (. ft.module-filetypes module-hook) 
                      [])]
    (set paredit-languages (mimis.concat paredit-languages languages))
    (plugins.register {:kovisoft/paredit {:for paredit-languages}})))

(fn setup []
  (set vim.g.paredit_leader ",")
  (set vim.g.paredit_matchlines 500)
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern paredit-languages
    :group (vim.api.nvim_create_augroup "mimis-paredit" {:clear true})
    :desc "Setup paredit for specific filetypes"
    :callback 
    (fn []
      (let [buffer (vim.api.nvim_get_current_buf)]

        (set vim.g.paredit_electric_return 0)

        (vim.cmd ":call PareditInitBuffer()")
        (vim.keymap.set "n" "<)" ":call PareditMoveLeft()<CR>" {:desc "slurp-backwords" :buffer buffer})
        (vim.keymap.set "n" ">)" ":call PareditMoveRight()<CR>" {:desc "slurp-forwards" :buffer buffer})
        (vim.keymap.set "n" "<R" ":call PareditSplice()<CR>" {:desc "unwrap-form" :buffer buffer})
        (vim.keymap.set "n" "<r" ":call PareditRaise()<CR>" {:desc "raise-form" :buffer buffer})))}))

{: enable
 : setup }
