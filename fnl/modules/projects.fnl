(local plugins (require :plugins))

(fn enable []
  (plugins.register {"airblade/vim-rooter" :always}))

(fn setup [options]
  (let [options (or options {:patterns ["project.clj" "shadow-cljs.edn" "pom.xml"]})]
    (set vim.g.rooter_patterns options.patterns)
    (set vim.g.rooter_silent_chdir 1)))

{: enable
 : setup }
