;; Agent subprocess: spawn, line-buffered stdout, raw debug log.

;; Every Neovim appends to the same log, so each line carries its process id.
(local pid (vim.fn.getpid))

(fn debug-path []
  (vim.fn.expand (or vim.g.acp-debug-log (.. (vim.fn.stdpath :log) "/acp-debug.log"))))

(fn debug [direction text]
  (let [stamp (os.date "%H:%M:%S")
        lines (icollect [_ l (ipairs (vim.split text "\n" {:plain true}))]
                (.. stamp " [" pid "] " direction " " l))]
    (vim.fn.writefile lines (debug-path) "a")))

(local debug-limit (* 2 1024 1024))

(fn rotate-debug []
  ;; Once the log passes the limit, keep it as .old and start fresh.
  (let [path (debug-path)]
    (when (> (vim.fn.getfsize path) debug-limit)
      (vim.fn.rename path (.. path ".old")))))

(fn clean-env [remove]
  ;; This Neovim's environment without the variables the agent's profile lists.
  (let [env (vim.fn.environ)]
    (each [_ name (ipairs (or remove []))]
      (tset env name nil))
    env))

(fn start [cmd cwd handlers env-remove sandbox]
  ;; sandbox, when given, is what modules.acp.sandbox.prepare returned: the argv that
  ;; wraps the agent and the environment that points it at the proxy.
  (var leftover "")
  (let [cmd (if (and sandbox sandbox.prefix)
              (vim.list_extend (vim.deepcopy sandbox.prefix) cmd)
              cmd)
        remove (vim.list_extend (vim.deepcopy (or env-remove []))
                                (if sandbox
                                  ;; A proxy inherited from the parent would be a way
                                  ;; around the sandbox's own.
                                  ["ALL_PROXY" "all_proxy"
                                   "HTTP_PROXY" "http_proxy"
                                   "HTTPS_PROXY" "https_proxy"
                                   "NO_PROXY" "no_proxy"]
                                  []))
        env (clean-env remove)]
    (each [name value (pairs (or (?. sandbox :env) {}))]
      (tset env name value))
    (rotate-debug)
    (debug "--" (.. "start " (table.concat cmd " ") " in " cwd))
    (let [on-stdout
          (fn [_ data]
            (when data
              (let [text (.. leftover data)
                    lines (vim.split text "\n" {:plain true})]
                (set leftover (table.remove lines))
                (vim.schedule
                  (fn []
                    (each [_ line (ipairs lines)]
                      (when (not= line "")
                        (debug "<-" line)
                        (handlers.on-line line))))))))
          on-stderr
          (fn [_ data]
            (when data
              (vim.schedule (fn [] (debug "!!" (data:gsub "\n$" ""))))))
          on-exit
          (fn [obj]
            (vim.schedule
              (fn []
                (debug "--" (.. "exit " obj.code))
                (handlers.on-exit obj.code))))
          (ok proc) (pcall vim.system cmd
                           {:cwd cwd
                            :env env
                            :clear_env true
                            :stdin true
                            :text true
                            :stdout on-stdout
                            :stderr on-stderr}
                           on-exit)]
      (if ok
        proc
        (do
          (debug "--" (.. "failed to start: " (tostring proc)))
          (values nil proc))))))

(fn send [proc line]
  (debug "->" line)
  (proc:write (.. line "\n")))

(fn stop [proc sandboxed?]
  (when (not (proc:is_closing))
    (pcall #(proc:write nil))
    ;; bwrap does not pass signals on: killing it alone leaves the agent, and the
    ;; namespace it holds open, running. The agent is bwrap's only child.
    (when sandboxed?
      (pcall vim.fn.system ["pkill" "-TERM" "-P" (tostring proc.pid)]))
    (proc:kill :sigterm)))

{: start
 : clean-env
 : send
 : stop
 : debug
 : debug-path}
