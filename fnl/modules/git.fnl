(local plugins (require :plugins))
(local mimis (require :mimis))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (mimis.try-add-treesitter-path :gitcommit "0.0.36-1")
  (plugins.register 
    {:tpope/vim-fugitive {:on [:G :Git :Gvdiffsplit :Gread]}
     :lewis6991/gitsigns.nvim :always }))

(fn setup []
  (mimis.leader-map 
    "n" 
    "gg" 
    ":silent vimgrep `git ls-files $(git rev-parse --show-toplevel)`<left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><left><space>" {:desc "find-in-git"})
  (mimis.leader-map "n" "gd" ":Gvdiffsplit<CR>" {:desc "git-diff"})
  (mimis.leader-map "n" "gs" ":G<CR>" {:desc "git-status"})

  (let [gs (require :gitsigns)] 
    (gs.setup)))

{: enable
 : setup
 : depends }
