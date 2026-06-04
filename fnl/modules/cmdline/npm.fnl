(local mimis (require :mimis))

(fn enable [])

(fn setup []
  (let [completion 
        (fn [arglead cmdline _]
  (vim.fn.sort
    (let [args (. (vim.api.nvim_parse_cmd cmdline {}) :args)
          done (if (= arglead "") (length args) (- (length args) 1))]
      (if (= done 0)
          ;; first arg: the npm subcommand
          (accumulate [results []
                       _ v (ipairs [:access :adduser :audit :bugs :cache :ci :completion
                                  :config :dedupe :deprecate :diff :dist-tag :docs :doctor
                                  :edit :exec :explain :explore :find-dupes :fund :get :help
                                  :help-search :hook :init :install :install-ci-test
                                  :install-test :link :ll :login :logout :ls :org :outdated
                                  :owner :pack :ping :pkg :prefix :profile :prune :publish
                                  :query :rebuild :repo :restart :root :run :run-script :search
                                  :set :shrinkwrap :star :stars :start :stop :team :test
                                  :token :uninstall :unpublish :unstar :update :version :view
                                  :whoami])]
            (mimis.add-match v arglead results))

          (and (= done 1) (= (. args 1) "run"))
          ;; second arg after `run`: the package.json scripts
          (let [runs (vim.fn.system "jq -r '.scripts // {} | keys[]' package.json 2>/dev/null")]
            (accumulate [results []
                         _ v (ipairs (mimis.split runs "\n"))]
              (mimis.add-match v arglead results)))

          []))))]
    (vim.api.nvim_create_user_command
      "Npm"
      (fn [opts]
        (let [args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.shell opts (.. "npm " args))))
      {:bang false :desc "NPM command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
