(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:catppuccin/nvim {:as :catppuccin}}))

(fn setup []
  (let [cat (require "catppuccin")]
    (cat.setup
      {:flavour :mocha
       :background
       {:dark :mocha}
       :term_colors true
       :integrations
       {:cmp true
        :treesitter true
        :which_key true
        :semantic_tokens true
        :rainbow_delimiters true}}))
  (vim.cmd.colorscheme :catppuccin-mocha)
  (vim.cmd "hi CodeLensReference guifg=#494D64 guibg=#1e1e2e cterm=italic gui=italic")
  (vim.cmd "hi WinSeparator guifg=#1e1e2e guibg=#1e1e2e cterm=italic gui=italic"))

{: setup 
 : enable}
