(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable []
  (plugins.register {"airblade/vim-rooter" :always}))

(fn setup [project-patterns]
  (let [mimis (require :mimis)]
    (set vim.g.rooter_patterns project-patterns)
    (set vim.g.rooter_silent_chdir 1)
    (mimis.leader-map "n" "pf" ":Telescope find_files<CR>" {:desc "project-files"})
    (let [wk (require :which-key)] 
      (wk.add 
        [{1 (.. nvim.g.mapleader "p") :group "projects"}]))))

{: enable
 : setup }
