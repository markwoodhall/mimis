(local plugins (require :plugins))

(fn depends []
  [:modules.projects])

(fn enable []
  (plugins.register {:hdima/python-syntax {:for :python}})
  (vim.lsp.config 
    :basedpyright 
    {:cmd [:basedpyright-langserver :--stdio]
     :filetypes [:python]
     :root_markers ["pyproject.toml"]})
  (vim.lsp.config 
    :ruff 
    {:cmd [:ruff :server]
     :filetypes [:python]
     :root_markers ["pyproject.toml"]}))

(var lsp-setup nil)
(fn setup []
  (vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :python
     :group (vim.api.nvim_create_augroup "mimis-python" {:clear true})
     :desc "Setup python mode"
     :callback 
     (fn [_]
       (vim.cmd "set makeprg=poetry\\ run\\ pytest\\ --tb=short\\ -q\\ -p\\ no:warnings")
       (vim.cmd "set errorformat=%f:%l:\\ %m,%-G%.%#")
       (set vim.g.python_highlight_all 1)
       (when (not lsp-setup) 
         (vim.lsp.enable :ruff)
         (vim.lsp.enable :basedpyright)
         (set lsp-setup true)))}))

{: enable 
 : setup 
 : depends }
