(local commands (require :commands))

(fn enable [])

(fn containers []
  (let [mimis (require :mimis)
        containers (vim.fn.system "docker ps --format \"{{json .}}\" | jq .Names | sed 's/\\\"//g'")]
    (mimis.split containers "\n")))

(fn get-last-switch [c]
  (let [mimis (require :mimis)]
    (mimis.first (mimis.split (mimis.last (mimis.split c (.. " -"))) " "))))

(fn setup [] 
  (let [completion 
        (fn [_ c]
          (vim.fn.sort
            (let [mimis (require :mimis)
                  c-parts (mimis.split c " ")
                  with-defaults (fn [c] ["--format" "-f" (unpack c)])
                  with-containers (fn [] (with-defaults (containers)))]
              (mimis.concat 
                (match (get-last-switch c)
                  "f" (mimis.split (vim.fn.glob "*docker-compose*") "\n")
                  _ [])
                (match (mimis.count-matches c "%s")
                  1 (commands.get-matches
                      [:run :exec :ps :build :pull :push :images :login
                       :logout :search :version :info :builder :compose :container
                       :context :image :manifest :network :plugin :system :trust
                       :volume :swarm :attach :commit :cp :create :diff :events :export
                       :history :import :inspect :kill :load :logs :pause :port :rename
                       :restart :rm :rmi :save :start :stats :stop :tag :top 
                       :unpause :update :wait]
                      (mimis.second c-parts)) 
                  2 (match (mimis.second c-parts)
                      "logs" (commands.get-matches 
                               (with-containers)
                               (mimis.nth c-parts 3))
                      "kill" (commands.get-matches 
                               (with-containers)
                               (mimis.nth c-parts 3))
                      "compose" (commands.get-matches 
                                  (with-defaults [:up :down])
                                  (mimis.nth c-parts 3))
                      "volume" (commands.get-matches 
                                 (with-defaults [:create :inspect :prune :rm])
                                 (mimis.nth c-parts 3))
                      _ (with-defaults []))
                  3 (match (mimis.nth c-parts 3)
                      "up" (commands.get-matches 
                                 (with-defaults [:--detach])
                                 (mimis.nth c-parts 4))
                      _ (with-defaults []))
                  _ (with-defaults []))))))]
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
