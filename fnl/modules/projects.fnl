(local Plug (. vim.fn "plug#"))

(fn enable []
  (Plug "airblade/vim-rooter"))

(fn setup [project-patterns]
  (set vim.g.rooter_patterns ["project.clj" "shadow-cljs.edn" "pom.xml" "*.sln"])
  (set vim.g.rooter_silent_chdir 1))

{: enable
 : setup }
