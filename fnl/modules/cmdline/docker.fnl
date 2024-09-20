(fn enable [])

(fn containers []
  (let [util (require :util)
        containers (vim.fn.system "docker ps --format \"{{json .}}\" | jq .Names    | sed 's/\\\"//g'")]
    (util.split containers "\n")))

(fn setup [] 
  (let [completion 
        (fn [_ c]
          (vim.fn.sort
            (let [mimis (require :mimis)
                  c-parts (mimis.split c " ")
                  with-defaults (fn [c] ["--format" (unpack c)])]
              (match (mimis.count-matches c "%s")
                0 []
                1 (accumulate 
                    [results []
                     _ v (ipairs [:run :exec :ps :build :pull :push :images :login
                                  :logout :search :version :info :builder :compose :container
                                  :context :image :manifest :network :plugin :system :trust
                                  :volume :swarm :attach :commit :cp :create :diff :events :export
                                  :history :import :inspect :kill :load :logs :pause :port :rename
                                  :restart :rm :rmi :save :start :stats :stop :tag :top 
                                  :unpause :update :wait])]
                    (mimis.add-match v (mimis.second c-parts) results))
                2 (match (mimis.second c-parts)
                    "logs" (with-defaults (containers))
                    "kill" (with-defaults (containers))
                    "compose" (with-defaults [:up :down])
                    "volume" (with-defaults [:create :inspect :prune :ls :rm])
                    _ (with-defaults []))
                3 (match (mimis.nth c-parts 3)
                    "up" ["--detach"])))))]
    (vim.api.nvim_create_user_command
      "Docker"
      (fn [opts]
        (let [mimis (require :mimis)
              args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.bottom-pane-shell (.. "docker " args))))
      {:bang false :desc "Docker command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
