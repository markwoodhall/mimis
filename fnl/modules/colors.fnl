(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable []
  (plugins.register
    {:catppuccin/nvim {:as :catppuccin}}))

(fn setup [options]
  (let [theme (when (not= options.theme :default)
                (require (or options.theme :catppuccin)))]
    (when (and theme options.settings)
      (theme.setup options.settings)))
  (set nvim.o.background options.background)
  (vim.cmd.colorscheme (or options.colorscheme options.theme :catppuccin))
  (vim.cmd.syntax :on))

{: setup 
 : enable}
