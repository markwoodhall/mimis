(local nvim (require :nvim))
(local mimis (require :mimis))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter])

(fn enable []
  (plugins.register
    {:nvim-orgmode/orgmode :always
     :lukas-reineke/headlines.nvim {:for :org}
     :akinsho/org-bullets.nvim {:for :org}
     :dhruvasagar/vim-table-mode {:for :org}}))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))
        og (require :orgmode)]
    (og.setup {:mappings {:disable_all true}})

    (vim.api.nvim_create_autocmd 
      "FileType" 
      {:pattern :org
       :group (vim.api.nvim_create_augroup "mimis-orgmode" {:clear true})
       :desc "Setup org mode"
       :callback 
       (partial 
         vim.schedule 
         (fn []
           (let [wk (require :which-key)
                 ob (require "org-bullets")
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
             (when (. o :notes)
               (require :modules.notes)
               (wk.add 
                [{1 (.. nvim.g.mapleader "m") :group "org" :buffer buffer}
                 {1 (.. nvim.g.mapleader "mn") :group "notes" :buffer buffer}]
                (mimis.leader-map "n" "mnn" ":NewNote" {:desc "new-note" :buffer buffer})
                (mimis.leader-map "n" "mnr" ":ReviewNote" {:desc "review-note" :buffer buffer})
                (mimis.leader-map "n" "mnp" ":ViewNotePdf" {:desc "view-note-pdf" :buffer buffer})
                (mimis.leader-map "n" "mnh" ":ViewNoteHtml" {:desc "view-note-html" :buffer buffer})))
             (when (.  o :org-babel-like)
               (let [vabel (require :modules.vabel)]
                 (wk.add 
                   [{1 (.. nvim.g.mapleader "m") :group "org" :buffer buffer}
                    {1 (.. nvim.g.mapleader "me") :group "evaluation" :buffer buffer}
                    {1 (.. nvim.g.mapleader "mt") :group "tangle" :buffer buffer}])
                 (mimis.leader-map "n" "mee" vabel.eval-code-block {:desc "eval-code-block" :buffer buffer})
                 (mimis.leader-map "n" "mtf" vabel.tangle-blocks {:desc "tangle-file" :buffer buffer}))))))})))

{: enable
 : setup 
 : depends }
