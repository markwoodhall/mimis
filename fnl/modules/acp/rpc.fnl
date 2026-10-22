;; JSON-RPC 2.0 over newline-delimited JSON, with requests in both directions.

(fn new [handlers]
  ;; handlers: {:send (fn [line]) :on-request (fn [method params id]) :on-notification (fn [method params])}
  {:next-id 1
   :pending {}
   :handlers handlers})

(fn write [rpc msg]
  (set msg.jsonrpc "2.0")
  (rpc.handlers.send (vim.json.encode msg)))

(fn request [rpc method params callback]
  (let [id rpc.next-id]
    (set rpc.next-id (+ id 1))
    (tset rpc.pending id callback)
    (write rpc {: id : method : params})
    id))

(fn notify [rpc method params]
  (write rpc {: method : params}))

(fn respond [rpc id result]
  (write rpc {: id : result}))

(fn respond-error [rpc id code message]
  (write rpc {: id :error {: code : message}}))

(fn method-not-found [rpc id method]
  (respond-error rpc id -32601 (.. "Method not found: " method)))

(fn receive [rpc line]
  (let [(ok msg) (pcall vim.json.decode line {:luanil {:object true :array true}})]
    (if (or (not ok) (not= (type msg) :table))
      (vim.notify (.. "acp: could not decode message: " line) vim.log.levels.WARN)
      (and msg.method (not= msg.id nil))
      (rpc.handlers.on-request msg.method (or msg.params {}) msg.id)
      msg.method
      (rpc.handlers.on-notification msg.method (or msg.params {}))
      (not= msg.id nil)
      (let [callback (. rpc.pending msg.id)]
        (tset rpc.pending msg.id nil)
        (when callback
          (callback msg.error msg.result))))))

(fn fail-all [rpc message]
  (let [pending rpc.pending]
    (set rpc.pending {})
    (each [_ callback (pairs pending)]
      (callback {:code -32000 : message} nil))))

{: new
 : request
 : notify
 : respond
 : respond-error
 : method-not-found
 : receive
 : fail-all}
