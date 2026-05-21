(fn enable [])

(fn setup []
  (let [completion 
        (fn [_ _]
          (vim.fn.sort
            []))]

    (vim.api.nvim_create_user_command
      "Chatgpt"
      (fn [opts]
        (let [mimis (require :mimis)
              args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))
              tmp (vim.fn.tempname)
              org (.. "/home/markwoodhall/.cache/mimis/chatgpt/" (vim.fn.fnameescape args) ".org")]
          (if (mimis.exists? org)
            (mimis.bottom-pane org false false false)
            (do
              (vim.fn.system (.. "echo \"" (vim.fn.shellescape args) "\" | chatgpt-cli chat > " tmp))
              (vim.fn.system (.. "pandoc -f markdown -t org -o " org " " tmp))
              (mimis.bottom-pane org false false false)))))
      {:bang false :desc "ChatpGPT command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
