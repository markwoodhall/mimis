(local nvim (require "nvim"))

(set nvim.o.mouse "a")
(set nvim.o.updatetime 500)
(set nvim.o.timeoutlen 500)
(set nvim.o.laststatus 3)
(set nvim.o.textwidth 0)
(set nvim.o.wrapmargin 0)
(set nvim.o.shiftwidth 4)
(set nvim.o.tabstop 4)
(set nvim.o.softtabstop 4)
(set nvim.o.tabline "0")
(set nvim.o.synmaxcol 9999)
(set nvim.o.completeopt "menu,menuone,noselect")
(set nvim.o.shell "zsh")
(set nvim.o.fileformat "unix")
(set nvim.o.fileformats "unix,dos")
(set nvim.o.clipboard "unnamedplus")
(set nvim.o.foldmethod "manual")
(set nvim.o.inccommand :nosplit)
(set nvim.o.encoding "utf-8")
(set nvim.o.signcolumn "number")
(set nvim.o.cmdheight 0) 

(nvim.ex.set :ruler)
(nvim.ex.set :undofile)
(nvim.ex.set :incsearch)
(nvim.ex.set :noshowmatch)
(nvim.ex.set :noshowmode)
(nvim.ex.set :showcmd)
(nvim.ex.set :hlsearch)
(nvim.ex.set :nowrap)
(nvim.ex.set :splitbelow)
(nvim.ex.set :hidden)
(nvim.ex.set :wildmenu)
(nvim.ex.set :expandtab)
(nvim.ex.set :lazyredraw)
(nvim.ex.set :nospell)
(nvim.ex.set :list)
(nvim.ex.set :relativenumber)
(nvim.ex.set :termguicolors)
(nvim.ex.set :ignorecase)
(nvim.ex.set :smartcase)
(nvim.ex.set :nofoldenable)

(set nvim.g.mapleader " ")
(set nvim.g.maplocalleader ",")

(set nvim.g.matchparen_timeout 10)
(set nvim.g.matchparen_insert_timeout 10)

(vim.cmd "set path+=**")
(vim.cmd "set grepprg=rg\\ --vimgrep")
(vim.cmd "set grepformat^=%f:%l:%c:%m")

;; Auto create directories
(vim.cmd "au BufWritePre,FileWritePre * if @% !~# '\\(://\\)' | call mkdir(expand('<afile>:p:h'), 'p') | endif")

(vim.api.nvim_create_autocmd 
    ["TermOpen"] 
    {:pattern "*"
     :group (vim.api.nvim_create_augroup "mimis-terminal-open" {:clear true})
     :desc "Autocmds for terminal open"
     :callback 
     (partial 
       vim.schedule 
       (fn [] 
         (vim.cmd.normal "G")
         ;; Set scrollback
         (nvim.ex.setlocal "scrollback=25000")))})

(vim.api.nvim_create_autocmd 
    ["BufWinEnter" "WinEnter"] 
    {:pattern "term://*"
     :group (vim.api.nvim_create_augroup "mimis-terminal-enter" {:clear true})
     :desc "Autocmds for terminal entry"
     :callback 
     (partial 
       vim.schedule 
       (fn [] 
         ;; Anchor bottom position in terminal windows
         ;; (vim.cmd.normal "G")
         ;; Set filetype to off
         (set vim.b.filetype :off)
         (set vim.b.syntax :off)
         (set vim.b.relativenumber false)
         (set vim.b.number false)
         (set vim.b.list false)
         (set vim.b.wrap false)))})

