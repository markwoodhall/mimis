(local plugins (require :plugins))

(fn enable []
  (plugins.register {"airblade/vim-rooter" :always}))

(fn setup [project-patterns]
  (set vim.g.rooter_patterns project-patterns)
  (set vim.g.rooter_silent_chdir 1))

{: enable
 : setup }
