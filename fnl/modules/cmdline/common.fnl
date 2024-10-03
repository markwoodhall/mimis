(local plugins (require :plugins))

(fn enable []
  (plugins.register {:tpope/vim-eunuch :always}))

(fn setup []
  (let [gather-args 
        (fn [opts] (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v)))
        completion 
        (fn [command _ c]
          (let [mimis (require :mimis)
                opts (mimis.split c " ")
                opt (mimis.last opts)]
            (if (= opt command)
              (mimis.glob "./*")
              (mimis.glob (.. (mimis.last opts) "*")))))]

    (vim.api.nvim_create_user_command
      "Psql"
      (fn [opts]
        (let [mimis (require :mimis)
              args (mimis.split (gather-args opts) " ")]
          (mimis.bottom-pane-shell 
            (.. "psql -h " (mimis.first args) 
                " -d " (mimis.second args) 
                " -U " (mimis.nth args 3) 
                " -p " (mimis.nth args 4) 
                " -P footer=off -P pager=off -P format=wrapped -q "))
          (vim.cmd "setlocal syntax=sql")))
      {:bang false :desc "psql wrapper" :nargs "*"
       :complete (fn []
                   (let [mimis (require :mimis)]
                     (if (mimis.exists? (vim.fn.expand "~/.local/share/mimis/psql.connections"))
                       (vim.fn.readfile (vim.fn.expand "~/.local/share/mimis/psql.connections"))
                       ["localhost database-name username port"])))})

    (vim.api.nvim_create_user_command
      "Sqlcmd"
      (fn [opts]
        (let [mimis (require :mimis)
              args (mimis.split (gather-args opts) " ")]
          (mimis.bottom-pane-shell 
            (.. "sqlcmd -S " (mimis.first args) 
                " -d " (mimis.second args) 
                " -U " (mimis.nth args 3) 
                " -P " (vim.fn.shellescape (mimis.nth args 4)) 
                ""))
          (vim.cmd "setlocal syntax=sql")))
      {:bang false :desc "Sqlcmd wrapper" :nargs "*"
       :complete (fn []
                   (let [mimis (require :mimis)]
                     (if (mimis.exists? (vim.fn.expand "~/.local/share/mimis/sqlcmd.connections"))
                       (vim.fn.readfile (vim.fn.expand "~/.local/share/mimis/sqlcmd.connections"))
                       ["localhost database-name username password"])))})

;;sqlcmd -S abdevdb01.database.windows.net -d abvin_test -U AdminTech

    (vim.api.nvim_create_user_command
      "Tail"
      (fn [opts]
        (let [mimis (require :mimis)
              args (gather-args opts)]
          (mimis.bottom-pane-shell (.. "tail " args))))
      {:bang false :desc "tail wrapper" :nargs "*"
       :complete (partial completion "Tail")})

    (vim.api.nvim_create_user_command
      "Logs"
      (fn [opts]
        (let [mimis (require :mimis)
              args (gather-args opts)]
          (mimis.bottom-pane-shell (.. "tail " args))
          (vim.cmd "setlocal syntax=json")))
      {:bang false :desc "Logs wrapper" :nargs "*"
       :complete (partial completion "Logs")})))

{: enable
 : setup }
