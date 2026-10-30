;; Default options
(local _ (require :modules.options))
(local package (require :packages.package))

(vim.cmd "packadd cfilter")

(package.enable 
  {;; Keymaps
   :modules.keymaps []

   ;; Structure and syntax
   :modules.surround []

   ;; Language support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.terraform []
   :modules.lisp []
   :modules.sql []
   :modules.packages.python []

   :modules.org []

   ;; Command line wrappers
   :modules.packages.cmdline []

   ;; Editor integrations
   :modules.git []
   :modules.statusline []
   :modules.quickfix []
   :modules.colors []
   :modules.acp []}
  :stable)

(set vim.g.mimis-notes-path "/home/markwoodhall/notes")
(set vim.g.mimis-notes-pandoc-opts "--data-dir=/home/markwoodhall/.pandoc --template default.html5 -c https://cdn.simplecss.org/simple.min.css")

;; ACP agents. :sandbox is the egress policy and the default for that agent; the
;; command line (:Acp sandbox / :Acp nosandbox) overrides it for one session.
;; This entry only adds the policy: the built-in command, :env-remove and credits
;; command are kept.
(set vim.g.acp-agents
     {:claude {:sandbox {:net :proxy
                           :allow ["api.anthropic.com:443"
                                   "mcp-proxy.anthropic.com:443"
                                   "http-intake.logs.us5.datadoghq.com:443"
                                   "downloads.claude.ai:443"
                                   "www.figma.com:443"
                                   "api.figma.com:443"
                                   "registry.npmjs.org:443"
                                   "docs.aws.amazon.com:443"
                                   "mcp.figma.com:443"
                                   "mcp.shortcut.com:443"
                                   "api.app.shortcut.com:443"]}}
     :opencode {:sandbox {:net :proxy
                           :allow ["models.opencode.ai:443"
                                   "opencode.ai:443"
                                   "www.figma.com:443"
                                   "api.figma.com:443"
                                   "registry.npmjs.org:443"
                                   "docs.aws.amazon.com:443"
                                   "mcp.figma.com:443"
                                   "mcp.shortcut.com:443"
                                   "api.app.shortcut.com:443"]}}})

;;(let [ui2 (require "vim._core.ui2")]
;;  (ui2.enable))

(package.setup
  {;; Keymaps
   :modules.keymaps []

   ;; Language Support
   :modules.packages.fennel []
   :modules.packages.clojure []
   :modules.terraform []
   :modules.lisp []
   :modules.sql []
   :modules.packages.python []

   :modules.org [:org-babel-like :notes]

   ;; Command line wrappers
   :modules.packages.cmdline []

   ;; Editor integration
   :modules.git []
   :modules.colors 
   {:theme :catppuccin
    :colorscheme :catppuccin-mocha
    :background :dark
    :post-setup (fn [])}
   :modules.statusline []
   :modules.quickfix [] 
   :modules.acp []

   ;; Structure and syntax
   :modules.surround []})
