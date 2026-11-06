;; A small MCP server over HTTP, for tools that Neovim answers itself.
;;
;; One POST, one JSON reply, connection closed: the part of Streamable HTTP that tools
;; need, with no server-sent events, so a GET is refused as the transport allows. It
;; listens on 127.0.0.1 and every request must carry the server's random bearer token.
;; A browser can reach loopback too, so anything with an Origin header is refused.
;;
;; A tool is {:name :description :inputSchema :run (fn [args done fail])}, and calls
;; (done value) with what to return as JSON, or (fail message). It may do so later.
;; A server's instructions, if any, are what its client is told about it as it connects.

(local protocol-versions ["2025-11-25" "2025-06-18" "2025-03-26"])
(local max-head (* 16 1024))
(local max-body (* 4 1024 1024))

(fn close [server client]
  (tset server.clients client nil)
  (when (not (client:is_closing))
    (client:close)))

(fn reply [server client status body]
  ;; The client may have gone while a tool was working.
  (when (not (client:is_closing))
    (let [body (or body "")]
      (client:write (.. "HTTP/1.1 " status "\r\n"
                        (if (= status "405 Method Not Allowed") "Allow: POST\r\n" "")
                        (if (= body "") "" "Content-Type: application/json\r\n")
                        "Content-Length: " (length body) "\r\n"
                        "Connection: close\r\n\r\n"
                        body)
                    #(close server client)))))

(fn parse-request [text]
  ;; nil while more is on its way, {:problem status} for what will never be served.
  (let [(_ head-end) (string.find text "\r\n\r\n" 1 true)]
    (if (not head-end)
      (when (> (length text) max-head)
        {:problem "431 Request Header Fields Too Large"})
      (let [lines (vim.split (string.sub text 1 (- head-end 4)) "\r\n" {:plain true})
            (method path) (string.match (. lines 1) "^(%u+) (%S+)")
            headers (collect [i line (ipairs lines)]
                      (when (> i 1)
                        (let [(name value) (string.match line "^([^:]+):%s*(.-)%s*$")]
                          (when name (values (string.lower name) value)))))
            size (tonumber (or headers.content-length "0"))
            body (string.sub text (+ head-end 1))]
        (if (or (not method) (not size))
          {:problem "400 Bad Request"}
          headers.transfer-encoding
          {:problem "411 Length Required"}
          (> size max-body)
          {:problem "413 Content Too Large"}
          (>= (length body) size)
          {: method : path : headers :body (string.sub body 1 size)})))))

(fn result-of [value]
  {:content [{:type :text :text (vim.json.encode value)}]
   :isError false})

(fn failure-of [message]
  {:content [{:type :text :text message}]
   :isError true})

(fn call-tool [server params finish]
  (var answered false)
  (let [tool (accumulate [found nil _ t (ipairs server.tools) &until found]
               (when (= t.name params.name) t))
        once (fn [result]
               (when (not answered)
                 (set answered true)
                 (finish result)))]
    (if (not tool)
      (once (failure-of (.. "unknown tool " (tostring params.name))))
      (let [(ok problem) (pcall tool.run (or params.arguments {})
                                #(once (result-of $1))
                                #(once (failure-of $1)))]
        (when (not ok)
          (once (failure-of (tostring problem))))))))

(fn tool-listing [server]
  (icollect [_ t (ipairs server.tools)]
    {:name t.name :description t.description :inputSchema t.inputSchema}))

(fn negotiate [requested]
  (if (vim.tbl_contains protocol-versions requested)
    requested
    (. protocol-versions 1)))

(fn dispatch [server client msg]
  (let [send (fn [fields]
               (set fields.jsonrpc "2.0")
               (set fields.id msg.id)
               (reply server client "200 OK" (vim.json.encode fields)))]
    (if (or (= msg.id nil) (not msg.method))
      ;; A notification, or a response to something: nothing to answer.
      (reply server client "202 Accepted")
      (case msg.method
        :initialize
        (send {:result {:protocolVersion (negotiate (?. msg :params :protocolVersion))
                        :capabilities {:tools (vim.empty_dict)}
                        :instructions server.instructions
                        :serverInfo {:name server.name :version "0.1.0"}}})
        :ping
        (send {:result (vim.empty_dict)})
        :tools/list
        (send {:result {:tools (tool-listing server)}})
        :tools/call
        (call-tool server (or msg.params {}) #(send {:result $1}))
        _
        (send {:error {:code -32601 :message (.. "Method not found: " msg.method)}})))))

(fn handle [server client request]
  (if request.problem
    (reply server client request.problem)
    (not= request.headers.authorization (.. "Bearer " server.token))
    (reply server client "401 Unauthorized")
    request.headers.origin
    (reply server client "403 Forbidden")
    (not= request.path "/mcp")
    (reply server client "404 Not Found")
    (not= request.method "POST")
    (reply server client "405 Method Not Allowed")
    (let [(ok msg) (pcall vim.json.decode request.body {:luanil {:object true :array true}})]
      (if (and ok (= (type msg) :table))
        (dispatch server client msg)
        (reply server client "400 Bad Request")))))

(fn accept [server]
  (let [client (vim.uv.new_tcp)]
    (var received "")
    (var handled false)
    (when (server.listener:accept client)
      (tset server.clients client true)
      (client:read_start
        (vim.schedule_wrap
          (fn [err chunk]
            (if (or err (not chunk))
              (close server client)
              (when (not handled)
                (set received (.. received chunk))
                (let [request (parse-request received)]
                  (when request
                    (set handled true)
                    (handle server client request)))))))))))

(fn stop [server]
  (when (not (server.listener:is_closing))
    (server.listener:close))
  (each [client (pairs server.clients)]
    (close server client)))

(fn start [name tools instructions]
  ;; A running server, {:port :url :token ...}, or nil and why not.
  (let [listener (vim.uv.new_tcp)
        server {: name : tools : instructions : listener
                :clients {}
                :token (pick-values 1 (string.gsub (vim.uv.random 32) "."
                                                   #(string.format "%02x" (string.byte $1))))}
        (bound bind-problem) (listener:bind "127.0.0.1" 0)
        (listening listen-problem) (when bound
                                     (listener:listen 64 (fn [err]
                                                           (when (not err) (accept server)))))]
    (if listening
      (do
        (set server.port (. (listener:getsockname) :port))
        (set server.url (.. "http://127.0.0.1:" server.port "/mcp"))
        server)
      (do
        (listener:close)
        (values nil (tostring (or bind-problem listen-problem)))))))

{: start
 : stop
 : parse-request}
