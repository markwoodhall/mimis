(local plugins (require :plugins))

(fn enable []
  (plugins.register 
    {:nvim-tree/nvim-web-devicons :always
     :nvim-lualine/lualine.nvim :always}))

(fn theme [name]
  (case name
    :palenightfall
    {:bg "#252837"
     :fg "#a6accd"
     :black "#393552"
     :red "#ff5370"
     :green "#c3e88d"
     :grey "#373354"
     :yellow "#ffcb6b"
     :blue "#82aaff"
     :magenta "#f07178"
     :cyan "#89ddff"
     :orange "#f78c6c"
     :violet "#bb80b3"}
    :duskfox
    {:bg "#191726"
     :fg "#eae8ff"
     :black "#393552"
     :red "#eb6f92"
     :green "#a3be8c"
     :grey "#373354"
     :yellow "#f6c177"
     :blue "#569fba"
     :magenta "#c4a7e7"
     :cyan "#9ccfd8"
     :orange "#ea9a97"
     :violet "#eb98c3"}
    :tokyonight
    {:bg "#24283b"
     :blue "#7aa2f7"
     :cyan "#7dcfff"
     :fg "#c0caf5"
     :grey "#292e42"
     :green "#9ece6a"
     :magenta "#bb9af7"
     :orange "#ff9e64"
     :violet "#9d7cd8"
     :red "#f7768e"
     :yellow "#e0af68"}
    :catppuccin 
    {:bg "#11111b"
     :blue "#74c7ec"
     :cyan "#94e2d5"
     :fg "#CDD6F4"
     :grey "#494D64"
     :green "#a6e3a1"
     :magenta "#ee99a0"
     :orange "#fab387"
     :red "#f38ba8"
     :violet "#c6a0f6"
     :yellow "#F9E2AF"}))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))
        lualine (require :lualine)
        colors (if (. o :catppuccin)
                 (theme :catppuccin)
                 (if (. o :tokyonight)
                   (theme :tokyonight)
                   (if (. o :duskfox)
                     (theme :duskfox)
                     (if (. o :palenightfall)
                       (theme :palenightfall)
                       (theme :catppuccin)))))]

    (local conditions
      {:buffer_not_empty (fn []
                           (not= (vim.fn.empty (vim.fn.expand "%:t")) 1))
       :check_git_workspace (fn []
                              (local filepath (vim.fn.expand "%:p:h"))
                              (local gitdir
                                (vim.fn.finddir :.git (.. filepath ";")))
                              (and (and gitdir (> (length gitdir) 0))
                                   (< (length gitdir) (length filepath))))
       :hide_in_width (fn [] (> (vim.fn.winwidth 0) 80))})

    (local config 
      {:inactive_sections {:lualine_a {}
                           :lualine_b {}
                           :lualine_c {}
                           :lualine_x {}
                           :lualine_y {}
                           :lualine_z {}}
       :options {:component_separators ""
                 :globalStatus true
                 :section_separators ""}
       :sections {:lualine_a {}
                  :lualine_b {}
                  :lualine_c {}
                  :lualine_x {}
                  :lualine_y {}
                  :lualine_z {}}})

    (fn active-lsp []
      (var msg "No Active Lsp")
      (let [buf-ft (vim.api.nvim_buf_get_option 0 :filetype)
            clients (vim.lsp.get_clients)]
        (if (= (next clients) nil)
          msg
          (do 
            (each [_ client (ipairs clients)]
              (local filetypes client.config.filetypes)
              (when (and filetypes
                         (not= (vim.fn.index filetypes buf-ft) (- 1)))
                (let [name client.name]
                  (set msg name))))
            msg))))

    (fn ins-left [component] (table.insert config.sections.lualine_c component))
    (fn ins-right [component] (table.insert config.sections.lualine_x component))

    (ins-left {1 (fn [] "▊")
               :color {:fg colors.blue}
               :padding {:left 0 :right 1}})

    (ins-left {1 (fn []
                   (vim.api.nvim_buf_get_option 0 :filetype))
               :color (fn []
                        (local mode-color
                          {"\019" colors.orange
                           "\022" colors.blue
                           :! colors.red
                           :R colors.violet
                           :Rv colors.violet
                           :S colors.orange
                           :V colors.blue
                           :c colors.magenta
                           :ce colors.red
                           :cv colors.red
                           :i colors.green
                           :ic colors.yellow
                           :n colors.red
                           :no colors.red
                           :r colors.cyan
                           :r? colors.cyan
                           :rm colors.cyan
                           :s colors.orange
                           :t colors.red
                           :v colors.blue})
                        {:fg (. mode-color (vim.fn.mode))})
               :padding {:right 1}})
    (ins-left {1 :filesize :cond conditions.buffer_not_empty})
    (ins-left {1 :filename
               :color {:fg colors.magenta :gui :bold}
               :cond conditions.buffer_not_empty})
    (ins-left [:location])
    (ins-left {1 :progress :color {:fg colors.fg :gui :bold}})
    (ins-left {1 :diagnostics
               :diagnostics_color {:color_error {:fg colors.red}
                                   :color_info {:fg colors.cyan}
                                   :color_warn {:fg colors.yellow}}
               :sources [:nvim_diagnostic]
               :symbols {:error "  " :info "  " :warn "  "}})

    (when (. o :lsp) 
      (ins-right {1 active-lsp
                 :color (fn [] (when (not= (active-lsp) "No Active Lsp") {:fg colors.green :gui :bold}))
                 :cond (fn [] (not= (active-lsp) "No Active Lsp"))
                 :icon " "}))
    (ins-right {1 "o:encoding"
                :color {:fg colors.grey :gui :bold}
                :cond conditions.hide_in_width
                :fmt string.upper})
    (ins-right {1 :fileformat
                :color {:fg colors.grey :gui :bold}
                :fmt string.upper
                :icons_enabled true})
    (ins-right {1 :branch :color {:fg colors.violet :gui :bold} :icon ""})
    (ins-right {1 :diff
                :cond conditions.hide_in_width
                :diff_color {:added {:fg colors.green}
                             :modified {:fg colors.orange}
                             :removed {:fg colors.red}}
                :symbols {:added "+ " :modified "~ " :removed "- "}})
    (ins-right {1 (fn [] "▊") :color {:fg colors.blue} :padding {:left 1}})
    (lualine.setup config)))

{: enable
 : setup }
