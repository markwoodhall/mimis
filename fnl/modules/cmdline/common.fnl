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
      "Tail"
      (fn [opts]
        (let [mimis (require :mimis)
              args (gather-args opts)]
          (mimis.bottom-pane-shell (.. "tail " args))))
      {:bang false :desc "Tail wrapper" :nargs "*"
       :complete (partial completion "Tail")})

    (vim.api.nvim_create_user_command
      "Logs"
      (fn [opts]
        (let [mimis (require :mimis)
              args (gather-args opts)]
          (mimis.bottom-pane-shell (.. "tail " args))
          (vim.cmd "setlocal syntax=json")))
      {:bang false :desc "Tail wrapper" :nargs "*"
       :complete (partial completion "Logs")})))

{: enable
 : setup }
