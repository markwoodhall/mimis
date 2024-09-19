(local plugins (require :plugins))
(local mimis (require :mimis))

(fn enable []
  (plugins.register
    {"nvim-lua/plenary.nvim" :always
     "nvim-telescope/telescope.nvim" :always
     "stevearc/dressing.nvim" :always}))

(fn setup []
  (let [ts (require :telescope)
        actions (require "telescope.actions")
        action_state (require "telescope.actions.state")]
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
                               "<C-k>" actions.move_selection_previous}}}})))

{: enable
 : setup}
