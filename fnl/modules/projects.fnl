(local plugins (require :plugins))

(fn enable []
  (plugins.register {"airblade/vim-rooter" :always}))

(local module-options
  {:modules.fennel {:patterns ["flsproject.fnl"]}
   :modules.clojure {:patterns ["project.clj" "shadow-cljs.edn" "pom.xml"]}})

(fn setup [options module-hook]
  (let [mimis (require :mimis)
        options 
        (or options 
            (. module-options module-hook) 
            {})]
    (when options.patterns
      (set vim.g.rooter_patterns (mimis.concat vim.g.rooter_patterns options.patterns)))
    (set vim.g.rooter_silent_chdir 1)))

{: enable
 : setup }
