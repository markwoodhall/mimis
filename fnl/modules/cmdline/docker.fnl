(local commands (require :commands))
(local mimis (require :mimis))

(fn enable [])

(fn containers []
  (let [containers (vim.fn.system "docker ps --format \"{{json .}}\" | jq .Names | sed 's/\\\"//g'")]
    (mimis.split containers "\n")))

(fn setup []
  (let [completion 
        (fn [arglead cmdline _]
          (let [args  (. (vim.api.nvim_parse_cmd cmdline {}) :args)
                comp  (let [w (vim.list_extend [] args)]
                        (when (= arglead "") (table.insert w ""))
                        w)
                out   (: (vim.system ["docker" "__complete" (unpack comp)] {:text true}) :wait)
                lines (mimis.split (or out.stdout "") "\n")]
            (vim.fn.sort
              (icollect [_ line (ipairs lines)]
                (when (and (not= line "") (not= (string.sub line 1 1) ":"))
                  (pick-values 1 (string.gsub line "\t.*$" "")))))))]
    (vim.api.nvim_create_user_command
      "Docker"
      (fn [opts]
        (let [args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.shell opts (.. "COMPOSE_MENU=false docker" args))))
      {:bang false :desc "Docker command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
