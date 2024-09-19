(local plugins (require :plugins))
(local nvim (require :nvim))
(local mimis (require :mimis))

(fn enable []
  (plugins.register 
    {"jaawerth/fennel.vim" {:for [:fennel]}}))

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
    data))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :fennel
     :group (vim.api.nvim_create_augroup "mimis-fennel" {:clear true})
     :desc "Setup fennel mode"
     :callback 
     (partial 
       vim.schedule 
       (fn []
         (let [r (require :modules.repl)]
           (m-binding "ss" (partial r.show-repl true) "jump-to-repl")
           (m-binding "sh" r.hide-repl "hide-repl")
           (m-binding "sx" r.kill-repl "kill-repl")
           (m-binding "si" (partial r.jack-in :fennel) "jack-in")
           (eval-binding "e" (partial r.send root-expression :none) "expression-to-repl"))
         (let [wk (require :which-key)
               buffer (vim.api.nvim_get_current_buf)] 
           (wk.add 
             [{1 (.. nvim.g.mapleader "m") :group "fennel" :buffer buffer}
              {1 (.. nvim.g.mapleader "ms") :group "sesman" :buffer buffer}
              {1 (.. nvim.g.mapleader "me") :group "evaluation" :buffer buffer}]))))}))

{: enable 
 : setup }
