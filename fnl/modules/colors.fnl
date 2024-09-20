(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:catppuccin/nvim {:as :catppuccin}
     :folke/tokyonight.nvim {:as :tokyonight}}))

(fn setup [options]
  (let [theme (require (or options.theme :catppuccin))]
    (when options.settings
      (theme.setup options.settings)))
  (vim.cmd.colorscheme (or options.theme :catppuccin)))

{: setup 
 : enable}
