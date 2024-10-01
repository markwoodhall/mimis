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

    (let [wk (require :which-key)] 
    (wk.add 
      [{1 (.. nvim.g.mapleader "p") :group "project"}]))
    
    (mimis.leader-map 
    "n" 
    "pt" 
    (fn [] 
      (let [project (vim.fn.call "FindRootDirectory" [])
            buff (. project-terminals project)]
        (if (and buff
                 (> (vim.fn.bufexists buff) 0))
          (mimis.bottom-pane-buff buff)
          (set (. project-terminals project) (- (mimis.bottom-pane-shell nvim.o.shell) 1)))))
    {:desc "toggle-project-terminal"})))

{: enable
 : setup }
