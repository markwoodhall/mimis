(fn enable [])

(fn setup []
  (fn lsp-status []
    (let [attached-clients (vim.lsp.get_clients {:bufnr 0})]
      (when (= (length attached-clients) 0) (lua "return \"\""))
      (local names (: (: (vim.iter attached-clients) :map
                         (fn [client]
                           (let [name (client.name:gsub :language.server :ls)]
                             name))) :totable))
      (.. "[" (table.concat names ", ") "]")))

  (fn _G.statusline []
    (table.concat ["%f" "%h%w%m%r" "%=" (lsp-status) " %-14(%l,%c%V%)" "%P"] " "))
  (set vim.o.statusline "%{%v:lua._G.statusline()%}")	)

{: enable
 : setup }
