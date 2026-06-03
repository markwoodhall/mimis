(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable []
  (plugins.register {:airblade/vim-rooter :always})
  (set vim.g.rooter_patterns [".git"]))

(local setup-hooks
  {:modules.fennel {:patterns ["flsproject.fnl"]}
   :modules.clojure {:patterns ["project.clj" "shadow-cljs.edn" "pom.xml"]}})

(local project-terminals {})

(fn setup [options module-hook]
  (let [mimis (require :mimis)
        options 
        (or options 
            (. setup-hooks module-hook) 
            {})]
    (when options.patterns
      (set vim.g.rooter_patterns (mimis.concat vim.g.rooter_patterns options.patterns)))
    (set vim.g.rooter_silent_chdir 1)

    (vim.api.nvim_create_user_command
    "PFiles"
    (fn [opts] 
      (let [patterns vim.g.rooter_patterns]
        (set vim.g.rooter_patterns [".git"])
        (let [project (vim.fn.call "FindRootDirectory" [])]
          (set vim.g.rooter_patterns patterns)
          (vim.cmd (.. opts.mods " e " project)))))
    {:bang false :desc "Project files" })
    
    (vim.api.nvim_create_user_command
    "PTerminal" 
    (fn [opts] 
      (let [project (vim.fn.call "FindRootDirectory" [])
            buff (. project-terminals project)]
        (if (and buff
                 (> (vim.fn.bufexists buff) 0))
          (mimis.buff opts buff)
          (set (. project-terminals project) (mimis.shell opts nvim.o.shell)))))
    {:bang false :desc "Project terminal" })))

{: enable
 : setup }
