(fn enable [])

(fn setup []
  (let [completion 
        (fn [_ c]
          (vim.fn.sort
            (let [mimis (require :mimis)
                  c-parts (mimis.split c " ")]
              (match (mimis.count-matches c "%s")
                0 []
                1 (accumulate 
                    [results []
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
                    (mimis.add-match v (mimis.second c-parts) results))
                2 (if (= (mimis.second c-parts) "run")
                    (let [runs 
                          (vim.fn.system 
                            "jq '.scripts|keys[]' package.json | sed 's/\\\"//g'")]
                      (mimis.split runs "\n"))
                    [])))))]
    (vim.api.nvim_create_user_command
      "Npm"
      (fn [opts]
        (let [mimis (require :mimis)
              args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.bottom-pane-shell (.. "npm " args))))
      {:bang false :desc "NPM command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
