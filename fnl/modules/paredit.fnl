(local nvim (require "nvim"))
(local Plug (. vim.fn "plug#"))

(var paredit-languages [])

(fn enable [languages]
  (Plug "kovisoft/paredit" {:for languages})
  (set vim.g.paredit_leader ",")
  (set vim.g.paredit_matchlines 1000)
  (set paredit-languages languages))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern paredit-languages
    :group (vim.api.nvim_create_augroup "paredit" {:clear true})
    :desc "Setup paredit for specific filetypes"
    :callback 
    (partial
      vim.schedule 
      (fn []
        (let [mimis (require :mimis) 
              buffer (vim.api.nvim_get_current_buf)
              wrap (fn [start end]
                     (vim.cmd (.. "call PareditWrap('" start "','" end "')")))]

          (set vim.g.paredit_electric_return 0)

          (mimis.leader-map "n" "sw(" (partial wrap "(" ")") {:desc "wrap-with-parens" :buffer buffer})
          (mimis.leader-map "n" "sw)" (partial wrap "(" ")") {:desc "wrap-with-parens" :buffer buffer})
          (mimis.leader-map "n" "sw[" (partial wrap "[" "]") {:desc "wrap-with-brackets" :buffer buffer})
          (mimis.leader-map "n" "sw]" (partial wrap "[" "]") {:desc "wrap-with-brackets" :buffer buffer})
          (mimis.leader-map "n" "sw{" (partial wrap "{" "}") {:desc "wrap-with-braces" :buffer buffer})
          (mimis.leader-map "n" "sw}" (partial wrap "[" "]") {:desc "wrap-with-braces" :buffer buffer})
          (mimis.leader-map "n" "sw'" (partial wrap "\' " "\'") {:desc "wrap-with-single-quotes" :buffer buffer})
          (mimis.leader-map "n" "sw\"" (partial wrap "\" " "\"") {:desc "wrap-with-double-quotes" :buffer buffer})
          (mimis.leader-map "n" "ssb" ":call PareditMoveLeft()<CR>" {:desc "slurp-backwords" :buffer buffer})
          (mimis.leader-map "n" "ssf" ":call PareditMoveRight()<CR>" {:desc "slurp-forwards" :buffer buffer})
          (mimis.leader-map "n" "suu" ":call PareditSplice()<CR>" {:desc "unwrap-form" :buffer buffer})
          (mimis.leader-map "n" "sur" ":call PareditRaise()<CR>" {:desc "raise-form" :buffer buffer})

          (let [wk (require :which-key)] 
            (wk.add 
              [{1 (.. nvim.g.mapleader "s") :group "smartparens" :buffer buffer}
               {1 (.. nvim.g.mapleader "sw") :group "wrap" :buffer buffer}
               {1 (.. nvim.g.mapleader "ss") :group "slurp" :buffer buffer}
               {1 (.. nvim.g.mapleader "su") :group "unwrap" :buffer buffer}])))))}))

{: enable
 : setup }
