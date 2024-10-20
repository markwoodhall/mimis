(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:catppuccin/nvim {:as :catppuccin}
     :EdenEast/nightfox.nvim {:as :nightfox}
     :JoosepAlviste/palenightfall.nvim {:as :palenightfall}
     :folke/tokyonight.nvim {:as :tokyonight}}))

(fn setup [options]
  (let [theme (require (or options.theme :catppuccin))]
    (when options.settings
      (theme.setup options.settings)))
  (set nvim.o.background options.background)
  (vim.cmd.colorscheme (or options.colorscheme options.theme :catppuccin)))

{: setup 
 : enable}
