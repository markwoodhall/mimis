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
(set nvim.o.completeopt "menu,menuone,noselect,fuzzy")
(set nvim.o.colorcolumn "80")
(set nvim.o.shell "zsh")
(set nvim.o.fileformat "unix")
(set nvim.o.fileformats "unix,dos")
(set nvim.o.clipboard "unnamedplus")
(set nvim.o.foldmethod "manual")
(set nvim.o.inccommand :nosplit)
(set nvim.o.encoding "utf-8")
(set nvim.o.signcolumn "number")
(set nvim.o.cmdheight 0) 
(set nvim.o.winborder :none) 
(set nvim.o.scrolloff 35) 
(set nvim.o.spelllang :en_gb) 

(nvim.ex.set :ruler)
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
(nvim.ex.set :autocomplete)

(set nvim.g.mapleader " ")
(set nvim.g.maplocalleader ",")
(set nvim.g.netrw_liststyle 1)

(set nvim.g.matchparen_timeout 10)
(set nvim.g.matchparen_insert_timeout 10)
(set nvim.g.netrw_banner 0)

(vim.cmd "set path+=**")
(vim.cmd "set wildignore+=**/node_modules/**")
(vim.cmd "set wildignore+=**/.git/**")
(vim.cmd "set wildignore+=**/.clj-kondo/**")
(vim.cmd "set wildignore+=**/cljs-test-runner-out/**")
(vim.cmd "set wildignore+=.shadow-cljs/**")
(vim.cmd "set wildignore+=**/deployment-temp/**")
(vim.cmd "set wildignore+=**/resources/public/js/compiled/**")
(vim.cmd "set wildignore+=**/.cpcache/**")
(vim.cmd "set wildignore+=**/.lsp/**")
(vim.cmd "set wildignore+=**/oil:/**")
(vim.cmd "set wildignore+=**/fugitive:/**")
(vim.cmd "set wildignore+=**/target/**")
(vim.cmd "set wildignore+=**/logs/**")

(vim.cmd "set grepprg=rg\\ --vimgrep")
(vim.cmd "set grepformat^=%f:%l:%c:%m")
(vim.cmd "set fillchars+=vert:\\ ")
(vim.cmd "set fillchars+=horiz:\\ ")

(set vim.o.undofile true)
(set vim.o.undolevels 10000)

(vim.cmd "autocmd FileType qf wincmd J")
(vim.cmd "autocmd FileType qf nmap <buffer> <cr> <cr>:lcl<cr>:ccl<cr>")
(vim.cmd "au BufWritePre,FileWritePre * if @% !~# '\\(://\\)' | call mkdir(expand('<afile>:p:h'), 'p') | endif")

(vim.api.nvim_create_autocmd 
    ["TermOpen"] 
    {:pattern "*"
     :group (vim.api.nvim_create_augroup "mimis-terminal-open" {:clear true})
     :desc "Autocmds for terminal open"
     :callback
     (fn []
       (when (not= (vim.fn.mode) "t")
         (vim.cmd.normal "G"))
       ;; Set scrollback
       (nvim.ex.setlocal "scrollback=25000"))})

(vim.api.nvim_create_autocmd 
    "FileType" 
    {:pattern :mail
     :group (vim.api.nvim_create_augroup "mimis-mail" {:clear true})
     :desc "Setup mail mode"
     :callback 
     (fn [_]
       (vim.cmd "set syntax=org")
       (vim.cmd "setlocal spell")
       (if (not= (os.getenv "AERC_ACCOUNT") "Personal")
           (do (set vim.opt_local.textwidth 0)
               (set vim.opt_local.wrap true)
               (set vim.opt_local.linebreak true))
           (set vim.opt_local.textwidth 72)))})
