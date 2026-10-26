;; Statusline. Colours come from the Catppuccin palette; if it is not installed the
;; groups stay undefined and the statusline renders plainly.

(fn palette []
  (let [(ok? palettes) (pcall require :catppuccin.palettes)]
    (when ok?
      (let [(ok? colours) (pcall palettes.get_palette)]
        (when ok? colours)))))

(fn define-highlights []
  (let [c (palette)]
    (when c
      (let [set-hl (fn [group spec] (vim.api.nvim_set_hl 0 group spec))
            bg c.mantle
            acp-bg c.surface0]
        (set-hl :StatusLineFile {:fg c.blue :bg bg})
        (set-hl :StatusLineFlags {:fg c.peach :bg bg})
        (set-hl :StatusLineLsp {:fg c.teal :bg bg})
        (set-hl :StatusLinePosition {:fg c.overlay1 :bg bg})
        (set-hl :AcpStatus {:fg c.lavender :bg acp-bg})
        (set-hl :AcpStatusName {:fg c.mauve :bg acp-bg :bold true})
        (set-hl :AcpStatusAgent {:fg c.peach :bg acp-bg :bold true})
        (set-hl :AcpStatusModel {:fg c.green :bg acp-bg})
        (set-hl :AcpStatusMode {:fg c.yellow :bg acp-bg})
        (set-hl :AcpStatusContext {:fg c.sky :bg acp-bg})
        (set-hl :AcpStatusContextWarn {:fg c.yellow :bg acp-bg})
        (set-hl :AcpStatusContextCritical {:fg c.red :bg acp-bg :bold true})
        (set-hl :AcpStatusCost {:fg c.teal :bg acp-bg})
        (set-hl :AcpStatusCredits {:fg c.sapphire :bg acp-bg})
        (set-hl :AcpStatusSeparator {:fg c.overlay1 :bg acp-bg})
        (set-hl :AcpStatusActivity {:fg c.pink :bg acp-bg :italic true})
        (set-hl :AcpStatusAlert {:fg c.red :bg acp-bg :bold true})
        true))))

(var highlighted? false)

(fn highlight []
  (when (not highlighted?)
    (set highlighted? (define-highlights))))

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

  (fn acp-status []
    (let [acp (. package.loaded :modules.acp.session)]
      (if acp (acp.status-text) "")))

  (fn _G.statusline []
    (highlight)
    (table.concat ["%#StatusLineFile#%f%*"
                   "%#StatusLineFlags#%h%w%m%r%*"
                   "%="
                   (acp-status)
                   (.. "%#StatusLineLsp#" (lsp-status) "%*")
                   "%#StatusLinePosition# %-14(%l,%c%V%) %P%*"] " "))

  (highlight)
  (vim.api.nvim_create_autocmd :ColorScheme
    {:group (vim.api.nvim_create_augroup "mimis-statusline" {:clear true})
     :desc "Reapply statusline highlights"
     :callback (fn []
                 (set highlighted? false)
                 (highlight))})
  (set vim.o.statusline "%{%v:lua._G.statusline()%}"))

{: enable
 : setup }
