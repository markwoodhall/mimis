(local mimis (require :mimis))

(fn enable [])

(fn setup []
  (let [completion 
        (fn [arglead cmdline _]
          (let [args  (. (vim.api.nvim_parse_cmd cmdline {}) :args)
                words (let [w (vim.list_extend ["npm"] args)]
                        (when (= arglead "") (table.insert w ""))
                        w)
                cword (- (length words) 1)
                line  (table.concat words " ")
                out   (: (vim.system ["npm" "completion" "--" (unpack words)]
                                     {:env {:COMP_CWORD (tostring cword)
                                            :COMP_LINE  line
                                            :COMP_POINT (tostring (length line))}
                                      :text true}) :wait)]
            (vim.fn.sort (mimis.split (or out.stdout "") "\n"))))]
    (vim.api.nvim_create_user_command
      "Npm"
      (fn [opts]
        (let [args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.shell opts (.. "npm " args))))
      {:bang false :desc "NPM command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
