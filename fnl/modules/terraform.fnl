(fn depends []
  [:modules.treesitter]
  [:modules.projects])

(fn enable []
  (set vim.o.runtimepath (.. vim.o.runtimepath ",$HOME/.local/share/nvim/plugged/ts/lib/luarocks/rocks-5.5/tree-sitter-hcl/0.0.35-1"))
  (vim.treesitter.language.register :hcl [:terraform]))

(fn setup [])

{: enable 
 : setup 
 : depends }
