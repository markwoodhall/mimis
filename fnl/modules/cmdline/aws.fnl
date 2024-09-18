(fn enable [])

(fn get-command-value [v c]
  (let [mimis (require :mimis)]
    (mimis.first (mimis.split (mimis.second (mimis.split c (.. v " "))) " "))))

(fn get-last-switch [c]
  (let [mimis (require :mimis)]
    (mimis.first (mimis.split (mimis.last (mimis.split c (.. " --"))) " "))))

(fn get-primary-command [c]
  (let [mimis (require :mimis)]
    (mimis.second (mimis.split c " "))))

(fn get-sub-command [c]
  (let [mimis (require :mimis)]
    (mimis.nth (mimis.split c " ") 3)))

(local get-profile (partial get-command-value "--profile"))

;; logs
(fn log-groups [command]
  (let [mimis (require :mimis) 
        profile (get-profile command)]
    (if profile
      (let [lgs (vim.fn.system (.. "aws --profile " profile " logs describe-log-groups | jq '.logGroups[].logGroupName'"))]
        (mimis.split lgs "\n"))
      [])))

;; sqs
(fn sqs-queues [command]
  (let [mimis (require :mimis)
        profile (get-profile command)]
    (if profile
      (let [lgs (vim.fn.system (.. "aws --profile " profile " sqs list-queues | jq '.QueueUrls[]'"))]
        (mimis.split lgs "\n"))
      [])))

;; ecs
(fn ecs-clusters [command]
  (let [mimis (require :mimis)
        profile (get-profile command)]
    (if profile
      (let [lgs (vim.fn.system (.. "aws --profile " profile " ecs list-clusters | jq '.clusterArns[]'"))]
        (mimis.split lgs "\n"))
      [])))

(fn ecs-services [command]
  (let [mimis (require :mimis)
        profile (get-profile command)
        cluster (get-command-value "--cluster" command)]
    (if profile
      (let [lgs (vim.fn.system (.. "aws --profile " profile " ecs list-services --cluster " cluster " | jq '.serviceArns[]'"))]
        (mimis.split lgs "\n"))
      [])))

(fn ecs-tasks [command]
  (let [mimis (require :mimis) 
        profile (get-profile command)
        cluster (get-command-value "--cluster" command)]
    (if (and profile cluster)
      (let [lgs (vim.fn.system (.. "aws --profile " profile " ecs list-tasks --cluster " cluster " | jq '.taskArns[]'"))]
        (mimis.split lgs "\n"))
      [])))

;; rds
(fn db-instances [command]
  (let [mimis (require :mimis)
        profile (get-profile command) ]
    (if profile
      (let [lgs (vim.fn.system (.. "aws --profile " profile " rds describe-db-instances | jq '.DBInstances[].DBInstanceIdentifier'"))]
        (mimis.split lgs "\n"))
      [])))

(fn profiles []
  (let [mimis (require :mimis)
        lgs (vim.fn.system "cat ~/.aws/config | grep '\\[profile ' | sed -e 's/\\[//g' -e 's/\\]//g' -e 's/profile //g'")]
    (mimis.split lgs "\n")))

(fn completer [command]
  (let [mimis (require :mimis)
        command (vim.fn.substitute command "Aws" "aws" "")
        lgs (vim.fn.system (.. "COMMAND_LINE='" command "' aws_completer"))
        col (mimis.split lgs "\n")]
    (accumulate 
      [c []
       _ v (ipairs col)]
      [(string.gsub v "%s+" "") (unpack c)])))

(fn for-service [c service f]
  (match (get-primary-command c)
    service (f c)
    _ []))

(fn for-command [c service command f]
  (match (get-primary-command c)
    service (match (get-sub-command c)
              command (f c)
              _ [])
    _ []))

(fn completion [_ c]
  (vim.fn.sort
    (let [mimis (require :mimis)
          c-parts (mimis.split c " ")
          with-defaults (fn [c] 
                          [(unpack c)])]
      (match (mimis.last c-parts)
        "--log-group-name" (for-service c :logs log-groups) 
        "--queue-url" (for-service c :sqs sqs-queues)
        "--cluster" (for-service c :ecs ecs-clusters)
        "--service-name" (for-service c :ecs ecs-services)
        "--tasks" (for-service c :ecs ecs-tasks)
        "--db-instance-identifier" (with-defaults (db-instances c))
        "--attribute-names" (for-command c :sqs :get-queue-attributes (fn [_] ["All"])) 
        "--profile" (profiles)
        "--start-time" (for-command c :logs :filter-log-events
                                    (fn [_] ["`date -d \"5 minutes ago\" +%s000`"
                                             "`date -d \"15 minutes ago\" +%s000`"
                                             "`date -d \"30 minutes ago\" +%s000`"
                                             "`date -d \"45 minutes ago\" +%s000`"
                                             "`date -d \"1 hour ago\" +%s000`"
                                             "`date -d \"2 hour ago\" +%s000`"
                                             "`date -d \"24 hours ago\" +%s000`"])) 
        "|" (for-command c :logs :filter-log-events (fn [_] [" jq '.events[].message | fromjson | {timestamp, exception}'"
                                                             " jq '.events[].message | fromjson | {timestamp, message}'"]))
        _ (match (get-last-switch c)
            "tasks" (with-defaults (ecs-tasks c))
            _ (with-defaults (completer (.. c ""))))))))

  (fn setup []
    (vim.api.nvim_create_user_command
      "Aws"
      (fn [opts]
        (let [mimis (require :mimis)
              args (accumulate 
                     [s ""
                      _ v (ipairs (?. opts :fargs))]
                     (.. s " " v))]
          (mimis.bottom-pane-shell (.. "aws" args))))
      {:bang false :desc "AWS command line wrapper" :nargs "*"
       :complete completion}))

  {: enable
   : setup }
