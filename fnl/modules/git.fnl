(local Plug (. vim.fn "plug#"))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn enable []
  (Plug "tpope/vim-fugitive" {:on [:G :Git :Gvdiffsplit]}))

(fn setup []
  (mimis.leader-map "n" "gd" ":Gvdiffsplit<CR>" {:desc "git-diff"})
  (mimis.leader-map "n" "gs" ":G<CR>" {:desc "git-status"})
  (let [wk (require :which-key)] 
    (wk.add 
      [{1 (.. nvim.g.mapleader "g") :group "git"}])))

{: enable
 : setup }
