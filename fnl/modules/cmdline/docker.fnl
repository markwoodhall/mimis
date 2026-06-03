(local commands (require :commands))
(local mimis (require :mimis))

(fn enable [])

(fn containers []
  (let [containers (vim.fn.system "docker ps --format \"{{json .}}\" | jq .Names | sed 's/\\\"//g'")]
    (mimis.split containers "\n")))

(fn setup []
  (let [completion 
        (fn [_ c]
          (vim.fn.sort
            (let [c-parts (mimis.split c " ")
                  with-defaults (fn [c] ["--format" (unpack c)])
                  with-containers (fn [] (with-defaults (containers)))]
              (mimis.concat 
               (mimis.concat
                (case (commands.get-last-single-switch c)
                  "f" (mimis.split (vim.fn.glob "*docker-compose*") "\n")
                  _ [])
                (case (commands.get-primary-command c)
                  "compose" (commands.get-matches
                                  (with-defaults [:up :down :-f])
                                  (mimis.nth c-parts 3))
                  _ []))
                (case (mimis.count-matches c "%s")
                  1 (commands.get-matches
                      [:run :exec :ps :build :pull :push :images :login
                       :logout :search :version :info :builder :compose :container
                       :context :image :manifest :network :plugin :system :trust
                       :volume :swarm :attach :commit :cp :create :diff :events :export
                       :history :import :inspect :kill :load :logs :pause :port :rename
                       :restart :rm :rmi :save :start :stats :stop :tag :top 
                       :unpause :update :wait]
                      (mimis.second c-parts)) 
                  2 (case (mimis.second c-parts)
                      "logs" (commands.get-matches 
                               (with-containers)
                               (mimis.nth c-parts 3))
                      "kill" (commands.get-matches 
                               (with-containers)
                               (mimis.nth c-parts 3))
                      "volume" (commands.get-matches
                                 (with-defaults [:create :inspect :prune :rm])
                                 (mimis.nth c-parts 3))
                      _ (with-defaults []))
                  3 (case (mimis.nth c-parts 3)
                      "up" (commands.get-matches 
                                 (with-defaults [:--detach])
                                 (mimis.nth c-parts 4))
                      _ (with-defaults []))
                  _ (with-defaults []))))))]
    (vim.api.nvim_create_user_command
      "Docker"
      (fn [opts]
        (let [args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.shell opts (.. "COMPOSE_MENU=false docker" args))))
      {:bang false :desc "Docker command line wrapper" :nargs "*"
       :complete completion})))

{: enable
 : setup }
