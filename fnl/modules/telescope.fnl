(local nvim (require "nvim"))
(local plugins (require :plugins))
(local mimis (require :mimis))

(fn enable []
  (plugins.register
    {:nvim-lua/plenary.nvim :always
     :nvim-telescope/telescope.nvim :always
     :stevearc/dressing.nvim :always}))

(fn setup [options]
  (let [o (accumulate 
            [r {} _ v (ipairs options)]
            (do (set (. r v ) v)
              r))
        wk (require :which-key)
        ts (require :telescope)
        dressing (require :dressing)
        actions (require "telescope.actions")
        action_state (require "telescope.actions.state")]

    (dressing.setup
      {:select {:enabled true
                :backend ["telescope" "builtin"]
                :trim_prompt true
                :telescope {:theme "ivy"}}})

    (ts.setup {:defaults 
               {:layout_strategy :bottom_pane
                :border false
                :sorting_strategy :ascending
                :layout_config {:height 0.3}
                :mappings {:i {"<C-j>" actions.move_selection_next
                               "<C-x>" (fn [b] 
                                         (vim.api.nvim_buf_delete
                                           (or (?. (action_state.get_selected_entry b) :bufnr)
                                               (tonumber (. (mimis.split (?. (action_state.get_selected_entry b) 1) ":") 1)))
                                           {:force true})
                                         (actions.close b)
                                         (vim.cmd ":Telescope buffers"))
                               "<C-p>" (fn [b] 
                                         (actions.close b)
                                         (mimis.bottom-pane-buff  
                                           (or (?. (action_state.get_selected_entry b) :bufnr)
                                               (tonumber (. (mimis.split (?. (action_state.get_selected_entry b) 1) ":") 1)))))
                               "<C-k>" actions.move_selection_previous}}}})

    (when (. o :buffers)
      (wk.add 
        [{1 (.. nvim.g.mapleader "b") :group "buffers"}])
      (mimis.leader-map "n" "bl" ":Telescope buffers<CR>" {:desc "list-buffers"}))

    (when (. o :git)
      (wk.add 
        [{1 (.. nvim.g.mapleader "g") :group "git"}])
      (mimis.leader-map "n" "gf" ":Telescope git_files<CR>" {:desc "git-files"})
      (mimis.leader-map "n" "gb" ":Telescope git_branches<CR>" {:desc "git-branches"})
      (mimis.leader-map "n" "gc" ":Telescope git_commits<CR>" {:desc "git-commits"}))

    (when (. o :finder)
      (wk.add 
        [{1 (.. nvim.g.mapleader "b") :group "finder"}])
      (mimis.leader-map "n" "ff" ":Telescope find_files hidden=true search_dirs={\"~/\"}<CR>" {:desc "find-files"})
      (mimis.leader-map "n" "fg" ":Telescope live_grep hidden=true<CR>" {:desc "grep"})
      (mimis.leader-map "n" "fr" ":lua require'telescope.builtin'.oldfiles{}<CR>" {:desc "recent-files"}))

    (when (. o :projects)
      (wk.add 
        [{1 (.. nvim.g.mapleader "p") :group "projects"}])
      (mimis.leader-map "n" "pf" ":Telescope find_files<CR>" {:desc "project-files"}))

    (when (. o :lsp)
      (wk.add 
        [{1 (.. nvim.g.mapleader "l") :group "lsp"}])
      (mimis.leader-map "n" "ldD" ":Telescope diagnostics<CR>" {:desc "project-diagnostics"})
      (mimis.leader-map "n" "ldd" ":Telescope diagnostics bufnr=0<CR>" {:desc "buffer-diagnostics"})
      (mimis.leader-map "n" "lgd" ":Telescope lsp_definitions<CR>" {:desc "go-to-definition"}) 
      (mimis.leader-map "n" "ldr" ":Telescope lsp_references<CR>" {:desc "references"}))))

{: enable
 : setup}
