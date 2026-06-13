(fn enable [])

(fn setup []
  (let [completion 
        (fn [_ _]
          (vim.fn.sort
            []))]

    (vim.cmd "cnoreabbrev mcache /home/markwoodhall/src/mark/kb/**/*.org")
    (vim.api.nvim_create_user_command
      "Chatgpt"
      (fn [opts]
        (let [mimis (require :mimis)
              args (table.concat opts.fargs " ")
              tmp (vim.fn.tempname)
              org (.. "/home/markwoodhall/src/mark/kb/"
                      (vim.fn.substitute args " " "-" "g")
                      ".org")]
          (if (and (not opts.bang) 
                   (mimis.exists? org))
            (mimis.file opts org)
            (do
              (vim.fn.system "mkdir -p ~/src/mark/kb")
              (vim.fn.system (.. "echo \"You behave like a search engine on steroids. I don't want any cruft, I will give you some keywords and you will answer. I want you to give me an overview of what you found first and foremost, and then some references with links I can follow. Don't acknowledge the request, just give me well formatted markdown and no emojis. Here are the keywords: " (vim.fn.shellescape args) "\" | chatgpt-cli chat > " tmp))
              (vim.fn.system ["pandoc" "-f" "markdown" "-t" "org" "-o" org tmp])
              (mimis.file opts org)))))
      {:bang true :desc "ChatpGPT command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
