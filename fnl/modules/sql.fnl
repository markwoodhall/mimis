(fn depends []
  [:modules.treesitter])

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-sql/0.0.55-1")))

(fn setup [])

{: enable
 : setup 
 : depends }
