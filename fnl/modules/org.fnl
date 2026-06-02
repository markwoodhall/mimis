(local mimis (require :mimis))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (plugins.register
    {:nvim-orgmode/orgmode :always
     :lukas-reineke/headlines.nvim {:for :org}
     :akinsho/org-bullets.nvim {:for :org} }))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))
        og (require :orgmode)]
    (og.setup {:mappings {:disable_all true} :org_startup_indented true})
    (when (. o :notes)
      (require :modules.notes))
    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern :org
       :group (vim.api.nvim_create_augroup "mimis-orgmode" {:clear true})
       :desc "Setup org mode"
       :callback 
       (fn []
         (let [ob (require "org-bullets")
                  headlines (require :headlines)
                  buffer (vim.api.nvim_get_current_buf)]
           (ob.setup)
           (headlines.setup
             {:org
             {:query
             (vim.treesitter.query.parse
               "org"
               "(headline (stars) @headline)

               (
                (expr) @dash
                (#match? @dash \"^-----+$\")
                )

               (block
                 name: (expr) @_name
                 (#match? @_name \"(SRC|src|QUOTE|quote)\")
                 ) @codeblock

               (paragraph . (expr) @quote
                          (#eq? @quote \">\")
                          )")}})
               
               (when (.  o :org-babel-like)
                 (let [vabel (require :modules.vabel)]
                   (mimis.leader-map "n" "mee" vabel.eval-code-block {:desc "eval-code-block" :buffer buffer})
                   (mimis.leader-map "n" "mtf" vabel.tangle-blocks {:desc "tangle-file" :buffer buffer})))))})))

{: enable
 : setup 
 : depends }
