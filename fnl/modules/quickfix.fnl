(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {"kevinhwang91/nvim-bqf" {:for :qf}}))

(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :qf
     :group (vim.api.nvim_create_augroup "mimis-quickfix" {:clear true})
     :desc "Setup quickfix mode"
     :callback 
     (partial
       vim.schedule 
       (fn []
         ;; Position the quickfix below and fix the size
         (vim.cmd "wincmd J")
         (vim.cmd "15wincmd_")))}))

{: enable
 : setup }
