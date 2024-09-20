(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:catppuccin/nvim {:as :catppuccin}
     :folke/tokyonight.nvim {:as :tokyonight}}))

(fn setup [options]
  (let [theme (require (or options.theme :catppuccin))]
    (when options.settings
      (theme.setup options.settings)))
  (vim.cmd.colorscheme (or options.theme :catppuccin-mocha))
  (vim.cmd "hi CodeLensReference guifg=#494D64 guibg=#1e1e2e cterm=italic gui=italic")
  (vim.cmd "hi WinSeparator guifg=#1e1e2e guibg=#1e1e2e cterm=italic gui=italic"))

{: setup 
 : enable}
