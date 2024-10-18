(local mimis (require :mimis))
(local nvim (require :nvim))
(local plugins (require :plugins))

(fn depends []
  [:modules.treesitter]
  [:modules.projects])

(fn m-binding [bind action desc]
  (mimis.leader-map
    "n"
    (.. "m" bind)
    action
    {:desc desc :buffer (vim.api.nvim_get_current_buf)}))

(fn eval-binding [bind action desc]
  (m-binding (.. "e" bind) action desc))

(fn root-expression []
  (let [ts-utils (require "nvim-treesitter.ts_utils")
        value (ts-utils.get_node_at_cursor 0 true)
        data (vim.treesitter.get_node_text value 0)]
    (.. data 
        "\r")))

(fn enable []
  (plugins.register {:janet-lang/janet.vim {:for :janet}})
  (set vim.g.clojure_max_lines 1000))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :janet
     :group (vim.api.nvim_create_augroup "mimis-janet" {:clear true})
     :desc "Setup janet mode"
     :callback 
     (partial 
       vim.schedule 
       (fn []
         (let [r (require :modules.repl)]

           (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
           (m-binding "sh" r.hide-repl "hide-repl")
           (m-binding "sx" r.kill-repl "kill-repl")
           (m-binding "si" (partial r.jack-in :janet) "jack-in")

           (eval-binding "e" (partial r.send root-expression :none) "expression-to-repl")

           (let [wk (require :which-key)
                 buffer (vim.api.nvim_get_current_buf)] 
             (wk.add 
               [{1 (.. nvim.g.mapleader "m") :group "janet" :buffer buffer}
                {1 (.. nvim.g.mapleader "ms") :group "sesman" :buffer buffer}
                {1 (.. nvim.g.mapleader "me") :group "evaluation" :buffer buffer}])))))}))

{: enable
 : setup 
 : depends }
