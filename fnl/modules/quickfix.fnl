(local Plug (. vim.fn "plug#"))

(fn enable [] 
  (Plug "kevinhwang91/nvim-bqf"))

(fn setup []
  (vim.cmd "autocmd FileType qf wincmd J")
  (vim.cmd "autocmd FileType qf nmap <buffer> <cr> <cr>:lcl<cr>:ccl<cr>"))

{: enable
 : setup }
