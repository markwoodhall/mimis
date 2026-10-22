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

(fn clean-env []
  ;; Never pass an API key through, or Claude Code bills the API instead of the subscription.
  (let [env (vim.fn.environ)]
    (tset env :ANTHROPIC_API_KEY nil)
    env))

(fn start [cmd cwd handlers]
  (var leftover "")
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
                          :env (clean-env)
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
        (values nil proc)))))

(fn send [proc line]
  (debug "->" line)
  (proc:write (.. line "\n")))

(fn stop [proc]
  (when (not (proc:is_closing))
    (pcall #(proc:write nil))
    (proc:kill :sigterm)))

{: start
 : send
 : stop
 : debug
 : debug-path}
