(local nvim (require "nvim"))
(local Plug (. vim.fn "plug#"))

(var paredit-languages [])
(var paredit-setup-done nil)

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
              wrap (fn [start end]
                     (vim.cmd (.. "call PareditWrap('" start "','" end "')")))]

          ;;(when (not paredit-setup-done)
              ;;  (vim.cmd "call PareditToggle()"))

          (set vim.g.paredit_electric_return 0)

          (mimis.leader-map "n" "sw(" (partial wrap "(" ")") {:desc "wrap-with-parens"})
                            (mimis.leader-map "n" "sw)" (partial wrap "(" ")") {:desc "wrap-with-parens"})
          (mimis.leader-map "n" "sw[" (partial wrap "[" "]") {:desc "wrap-with-brackets"})
                                    (mimis.leader-map "n" "sw]" (partial wrap "[" "]") {:desc "wrap-with-brackets"})
          (mimis.leader-map "n" "sw{" (partial wrap "{" "}") {:desc "wrap-with-braces"})
                                    (mimis.leader-map "n" "sw}" (partial wrap "[" "]") {:desc "wrap-with-braces"})
          (mimis.leader-map "n" "sw'" (partial wrap "\' " "\'") {:desc "wrap-with-single-quotes"})
          (mimis.leader-map "n" "sw\"" (partial wrap "\" " "\"") {:desc "wrap-with-double-quotes"})
          (mimis.leader-map "n" "ssb" ":call PareditMoveLeft()<CR>" {:desc "slurp-backwords"})
          (mimis.leader-map "n" "ssf" ":call PareditMoveRight()<CR>" {:desc "slurp-forwards"})
          (mimis.leader-map "n" "suu" ":call PareditSplice()<CR>" {:desc "unwrap-form"})
          (mimis.leader-map "n" "sur" ":call PareditRaise()<CR>" {:desc "raise-form"})
          (let [wk (require :which-key)] 
            (wk.add 
              [{1 (.. nvim.g.mapleader "s") :group "smartparens"}
               {1 (.. nvim.g.mapleader "sw") :group "wrap"}
               {1 (.. nvim.g.mapleader "ss") :group "slurp"}
               {1 (.. nvim.g.mapleader "su") :group "unwrap"}]))

          (set paredit-setup-done true))))}))

{: enable
 : setup }
