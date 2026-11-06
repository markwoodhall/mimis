;; End-to-end tests for delegation: the MCP server and the broker, driven over real HTTP
;; with curl, against test/acp/fake_agent.py. Needs neither bwrap nor a real agent.
;; Run from the repository:
;;   nvim --headless -c "lua require('fennel').dofile(vim.fn.stdpath('config') .. '/test/acp/broker_test.fnl')"
;; Exits non-zero if anything fails.

(local here (.. (vim.fn.stdpath :config) "/test/acp"))
(local fake ["python3" (.. here "/fake_agent.py")])
(set vim.g.acp-agent-cmd fake)
(set vim.g.acp-agents
     {:claude {:delegate ["opencode" "broken" "nomcp" "extra"]}
      :opencode (vim.list_extend (vim.deepcopy fake) ["opencode"])
      :other (vim.list_extend (vim.deepcopy fake) ["other"])
      :broken ["/nonexistent/agent"]
      :extra (vim.list_extend (vim.deepcopy fake) ["extra"])
      ;; An agent that can't take MCP servers over HTTP, and one that may delegate.
      :nomcp {:cmd (vim.list_extend (vim.deepcopy fake) ["nomcp" "nomcp"]) :delegate true}
      :boxless {:cmd fake :delegate true :sandbox {:net false}}
      :nothing {:cmd fake :delegate ["no-such-agent"]}
      :watched {:cmd fake :sandbox {:net :proxy :allow ["a.example:443"]}}})
(set vim.g.acp-credits false)
(set vim.g.acp-log-dir (vim.fn.tempname))
(set vim.g.acp-debug-log (vim.fn.tempname))
(set vim.g.acp-config-cache (vim.fn.tempname))
(set vim.g.acp-egress-log-dir (vim.fn.tempname))
(set vim.g.acp-notify false)

(local session (require :modules.acp.session))
(local mcp (require :modules.acp.mcp))
(local sandbox (require :modules.acp.sandbox))
(local protocol (require :modules.acp.protocol))
(local failures [])

(fn out [line]
  (io.stdout:write (.. line "\n")))

(fn check [name ok detail]
  (if ok
    (out (.. "ok   " name))
    (do
      (table.insert failures name)
      (out (.. "FAIL " name (if (not= detail nil) (.. "\n     " (vim.inspect detail)) ""))))))

(fn wait [pred ms]
  (vim.wait (or ms 5000) pred 10))

(fn lines-of [buf]
  (vim.api.nvim_buf_get_lines buf 0 -1 false))

(fn has-line [lines text]
  (accumulate [found false _ l (ipairs lines)]
    (or found (not= nil (string.find l text 1 true)))))

;; HTTP ------------------------------------------------------------------------------
;; curl runs asynchronously: the server it talks to is in this process, so this one has
;; to keep turning its event loop while it waits.

(fn http [url opts]
  ;; {:status :body}, or {:status 0} when nothing answered.
  (let [opts (or opts {})
        cmd ["curl" "-s" "--noproxy" "*" "--max-time" "70" "-w" "\n%{http_code}"
             "-X" (or opts.method "POST")]]
    (each [_ h (ipairs (or opts.headers []))]
      (vim.list_extend cmd ["-H" h]))
    (when opts.body
      (vim.list_extend cmd ["--data-binary" opts.body]))
    (table.insert cmd url)
    (var done nil)
    (vim.system cmd {:text true} (fn [r] (set done r)))
    (vim.wait 75000 #done 10)
    (let [parts (vim.split done.stdout "\n" {:plain true})
          status (tonumber (table.remove parts))]
      {:status (or status 0) :body (table.concat parts "\n")})))

(var server-url nil)
(var server-token nil)

(fn post [body]
  (http server-url {:headers ["Content-Type: application/json"
                              (.. "Authorization: Bearer " server-token)]
                    :body (vim.json.encode body)}))

(var next-id 0)

(fn rpc [method params]
  (set next-id (+ next-id 1))
  (let [r (post {:jsonrpc "2.0" :id next-id : method :params (or params (vim.empty_dict))})]
    (vim.json.decode r.body {:luanil {:object true :array true}})))

(fn call-tool [name args]
  ;; The tool's JSON, and whether it was an error.
  (let [reply (rpc "tools/call" {: name :arguments (or args (vim.empty_dict))})
        res reply.result
        text (. res :content 1 :text)]
    (if res.isError
      (values nil text)
      (vim.json.decode text {:luanil {:object true :array true}}))))

;; Parsing ---------------------------------------------------------------------------

(check "a request still arriving isn't parsed yet"
       (= nil (mcp.parse-request "POST /mcp HTTP/1.1\r\nContent-Le")))
(check "a body still arriving isn't parsed yet"
       (= nil (mcp.parse-request "POST /mcp HTTP/1.1\r\nContent-Length: 5\r\n\r\nabc")))
(let [r (mcp.parse-request "POST /mcp HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabcdef")]
  (check "a whole request parses, with lower-case header names and its exact body"
         (and (= "POST" r.method) (= "/mcp" r.path) (= "x" r.headers.host) (= "abc" r.body))
         r))
(check "a chunked body is refused"
       (= "411 Length Required"
          (?. (mcp.parse-request "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
              :problem)))
(check "an oversized body is refused"
       (= "413 Content Too Large"
          (?. (mcp.parse-request "POST /mcp HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")
              :problem)))

;; The sandbox spec ------------------------------------------------------------------

(let [s (sandbox.forward {:net :proxy :allow ["a.example:443"]} 4242)]
  (check "a sandboxed agent's port is forwarded and allowed"
         (and (vim.tbl_contains (. s :local) 4242)
              (vim.tbl_contains s.allow "localhost:4242")
              (vim.tbl_contains s.allow "a.example:443"))
         s))
(check "forwarding doesn't turn a sandbox on" (= nil (sandbox.forward nil 4242)))
(let [s (sandbox.forward {:net false} 4242)]
  (check "forwarding doesn't give a sandbox without network any"
         (and (= false s.net) (= nil s.allow)) s))

;; Through the egress proxy -----------------------------------------------------------
;; The real proxy, on a real socket, as a sandboxed agent's relay would use it. Only bwrap
;; is left out, so this runs wherever the proxy can make its socket.

(local tunnel-script "
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
s.sendall(('CONNECT localhost:%s HTTP/1.1\\r\\n\\r\\n' % sys.argv[2]).encode())
print(s.recv(4096).split(b'\\r\\n')[0].decode())
body = sys.argv[3]
s.sendall(('POST /mcp HTTP/1.1\\r\\nHost: x\\r\\nAuthorization: Bearer %s\\r\\nContent-Length: %d\\r\\n\\r\\n%s'
           % (sys.argv[4], len(body), body)).encode())
reply = b''
while True:
    chunk = s.recv(4096)
    if not chunk:
        break
    reply += chunk
print(reply.decode())
")

(let [broker (require :modules.acp.broker)
      agent {:name "claude" :delegate ["opencode"] :sandbox {:net :proxy :allow ["a.example:443"]}}
      b (broker.open agent #nil)
      port b.server.port
      (box problem) (sandbox.prepare agent.sandbox (vim.fn.getcwd))]
  (if (not box)
    (out (.. "skip the proxy route: " (tostring problem)))
    (do
      (check "the sandbox relay is told to forward the broker's port"
             (let [prefix box.prefix]
               (accumulate [found false i a (ipairs prefix)]
                 (or found (and (= a "--forward") (= (. prefix (+ i 1)) (tostring port))))))
             box.prefix)
      (var done nil)
      (vim.system ["python3" "-I" "-c" tunnel-script box.sock (tostring port)
                   (vim.json.encode {:jsonrpc "2.0" :id 1 :method "ping"})
                   b.server.token]
                  {:text true}
                  (fn [r] (set done r)))
      (vim.wait 10000 #done 10)
      (check "the proxy lets the broker's port through without asking"
             (and done (not= nil (string.find done.stdout "200 Connection established" 1 true)))
             done)
      (check "and an MCP request is answered through it"
             (and done (not= nil (string.find done.stdout "\"id\":1" 1 true))
                  (not= nil (string.find done.stdout "\"result\"" 1 true)))
             done)
      (sandbox.stop box)))
  (broker.close b))

;; Who gets a broker -----------------------------------------------------------------

(fn start-and-ask-servers [args]
  (vim.cmd (.. "Acp! " args))
  (let [s (session.current)]
    (wait #s.ready)
    (session.send-prompt s "mcp servers")
    (wait #s.last-turn)
    (values s (vim.json.decode (. s :last-turn :reply)))))

(let [(s servers) (start-and-ask-servers "other")]
  (check "a profile without :delegate gets no tools" (= 0 (length servers)) servers)
  (check "and no count in its statusline" (= nil (string.find (session.status-text) "agent " 1 true)))
  (vim.cmd "AcpStop"))

(do
  (var warned nil)
  (let [notify vim.notify]
    (set vim.notify (fn [m] (set warned m)))
    (vim.cmd "Acp! nothing")
    (set vim.notify notify))
  (check "a :delegate naming nothing known says so"
         (and warned (not= nil (string.find warned "names no known agent" 1 true))) warned)
  (vim.cmd "AcpStop"))

(do
  (var warned nil)
  (let [notify vim.notify]
    (set vim.notify (fn [m] (when (string.find m "delegation" 1 true) (set warned m))))
    (vim.cmd "Acp! boxless")
    (set vim.notify notify))
  (check "a sandbox with no network can't delegate, and says so"
         (and warned (not= nil (string.find warned "no network" 1 true))) warned)
  (vim.cmd "AcpStop"))

;; The server ------------------------------------------------------------------------

(local (parent servers) (start-and-ask-servers "claude"))
(local server (. servers 1))
(check "a delegating profile is handed one HTTP server"
       (and (= 1 (length servers)) (= "http" server.type)
            (= "Authorization" (. server :headers 1 :name)))
       servers)
(set server-url server.url)
(set server-token (string.match (. server :headers 1 :value) "^Bearer (.+)$"))
(check "it listens on loopback" (vim.startswith server-url "http://127.0.0.1:") server-url)
(check "the token is long and random" (= 64 (length server-token)))

(check "the token stays out of the debug log"
       (let [debug-log (table.concat (vim.fn.readfile vim.g.acp-debug-log) "\n")]
         (and (= nil (string.find debug-log server-token 1 true))
              (not= nil (string.find debug-log "Bearer [redacted]" 1 true)))))

(check "no token, no answer" (= 401 (. (http server-url {:body "{}"}) :status)))
(check "the wrong token, no answer"
       (= 401 (. (http server-url {:headers ["Authorization: Bearer nope"] :body "{}"}) :status)))
(let [auth (.. "Authorization: Bearer " server-token)]
  (check "a browser's request is refused even with the token"
         (= 403 (. (http server-url {:headers [auth "Origin: https://example.invalid"] :body "{}"})
                   :status)))
  (check "only /mcp is served"
         (= 404 (. (http (string.gsub server-url "/mcp$" "/other") {:headers [auth] :body "{}"})
                   :status)))
  (check "a GET is refused, as no event stream is offered"
         (= 405 (. (http server-url {:method "GET" :headers [auth]}) :status)))
  (check "a body that isn't JSON is a bad request"
         (= 400 (. (http server-url {:headers [auth] :body "not json"}) :status))))

(let [reply (rpc "initialize" {:protocolVersion "2025-06-18"
                               :capabilities (vim.empty_dict)
                               :clientInfo {:name "test" :version "0"}})]
  (check "initialize agrees a version the client offered"
         (= "2025-06-18" reply.result.protocolVersion) reply)
  (check "and offers tools" (not= nil reply.result.capabilities.tools) reply))
(let [reply (rpc "initialize" {:protocolVersion "1999-01-01"})]
  (check "a version it doesn't know gets the newest it does"
         (= "2025-11-25" reply.result.protocolVersion) reply))
(check "a notification is accepted with no reply"
       (let [r (post {:jsonrpc "2.0" :method "notifications/initialized"})]
         (and (= 202 r.status) (= "" r.body))))
(check "ping answers" (not= nil (. (rpc "ping") :result)))
(check "an unknown method is an error"
       (= -32601 (?. (rpc "no/such") :error :code)))

(let [tools (. (rpc "tools/list") :result :tools)
      names (vim.tbl_map #$1.name tools)]
  (table.sort names)
  (check "the tools are listed"
         (vim.deep_equal ["agent_cancel" "agent_list" "agent_result" "agent_send" "agent_start"
                          "agent_status" "agent_stop" "agent_wait"]
                         names)
         names)
  (let [start (accumulate [found nil _ t (ipairs tools) &until found]
                (when (= t.name "agent_start") t))]
    (check "agent_start can't set a mode, which could turn permission prompts off"
           (= nil (. start :inputSchema :properties :mode)))))

(let [(_ problem) (call-tool "no_such_tool")]
  (check "an unknown tool is a tool error" (not= nil (string.find problem "unknown tool" 1 true))))

;; Starting a child ------------------------------------------------------------------

(let [listed (call-tool "agent_list")]
  (check "only the profile's agents can be started"
         (vim.deep_equal ["opencode" "broken" "nomcp" "extra"] listed.available) listed))
(let [(_ problem) (call-tool "agent_start" {:agent "other" :prompt "plain"})]
  (check "an agent the profile doesn't name is refused" (not= nil problem) problem))
(let [(_ problem) (call-tool "agent_start" {:agent "opencode" :prompt "  "})]
  (check "an empty prompt is refused" (not= nil problem) problem))
(check "and neither started anything" (= 0 (length (session.children parent))))

(local started (call-tool "agent_start" {:agent "opencode" :prompt "plain"}))
(check "agent_start returns an id at once" (= "opencode-1" started.id) started)

(fn child-session []
  (. (session.children parent) 1))

(local child (child-session))
(check "the child is a session of its own" (and child (not= child parent)))
(check "the parent stays the current session" (= parent (session.current)))
(check "the parent's chat keeps its name, the child's is told apart"
       (and (vim.endswith (vim.api.nvim_buf_get_name parent.buf) "/nvim")
            (vim.endswith (vim.api.nvim_buf_get_name child.buf) "/nvim/opencode-1"))
       [(vim.api.nvim_buf_get_name parent.buf) (vim.api.nvim_buf_get_name child.buf)])
(check "its chat opens no window and takes no focus"
       (and (= -1 (vim.fn.bufwinid child.buf))
            (= parent.buf (vim.api.nvim_get_current_buf))))
(check "the parent's chat says it started"
       (has-line (lines-of parent.buf) "> acp: started opencode-1"))

(let [done (call-tool "agent_wait" {:id "opencode-1"})]
  (check "agent_wait returns when the turn ends, with the reply"
         (and (= "idle" done.state) (= false done.timed_out)
              (= "Plain reply." done.reply) (= "end_turn" done.stop_reason))
         done))
(let [result (call-tool "agent_result" {:id "opencode-1"})]
  (check "agent_result gives the same reply" (= "Plain reply." result.reply) result))

(check "a child gets no tools, so delegation stops one level down"
       (do
         (call-tool "agent_send" {:id "opencode-1" :prompt "mcp servers"})
         (let [done (call-tool "agent_wait" {:id "opencode-1"})]
           (= "[]" done.reply))))

(check "the child's log names its parent"
       (let [path child.log.path
             head (vim.fn.readfile path "" 12)]
         (and (vim.tbl_contains head (.. "parent: " parent.session.id))
              (vim.tbl_contains head "label: opencode-1"))))
(let [(_ problem) (call-tool "agent_status" {:id "nobody-1"})]
  (check "an id that doesn't exist is a tool error" (not= nil problem)))

;; The user stays in charge of permissions ------------------------------------------

(call-tool "agent_send" {:id "opencode-1" :prompt "long command"})
(let [paused (call-tool "agent_wait" {:id "opencode-1"})]
  (check "agent_wait returns when the child needs the user"
         (and (= "waiting_for_user" paused.state) (= false paused.timed_out)
              (= 1 (length paused.waiting_for_user))
              (vim.startswith (. paused.waiting_for_user 1) "permission: "))
         paused))
(check "the statusline flags it"
       (not= nil (string.find (session.status-text) "1 waiting" 1 true))
       (session.status-text))
(let [(_ problem) (call-tool "agent_send" {:id "opencode-1" :prompt "plain"})]
  (check "a child waiting for you takes no prompts" (not= nil problem) problem))

;; :AcpAllow acts on the chat you're in, so it can't approve what you can't see.
(vim.cmd "silent! AcpAllow")
(check ":AcpAllow from the parent's chat leaves the child's request alone"
       (not= nil child.permission))

(let [select vim.ui.select]
  (var offered nil)
  (var formatted nil)
  (set vim.ui.select (fn [items opts on-choice]
                       (set offered items)
                       (set formatted (vim.tbl_map opts.format_item items))
                       (on-choice (. items 2))))
  (vim.cmd "AcpAgents")
  (set vim.ui.select select)
  (check ":AcpAgents lists the session and its children"
         (and offered (= 2 (length offered)) (= parent (. offered 1)) (= child (. offered 2)))
         formatted)
  (check "and says what each is doing"
         (and formatted (not= nil (string.find (. formatted 2) "opencode-1 — waiting_for_user — permission:" 1 true)))
         formatted))
(check "choosing one shows its chat" (= child.buf (vim.api.nvim_get_current_buf)))
(check "the statusline in a child's chat names it"
       (not= nil (string.find (session.status-text) "opencode-1" 1 true))
       (session.status-text))

(vim.cmd "AcpAllow")
(check ":AcpAllow in the child's chat answers it" (= nil child.permission))
(let [done (call-tool "agent_wait" {:id "opencode-1"})]
  (check "and the child carries on to the end of its turn"
         (and (= "idle" done.state) (= 3 done.turns_finished)
              (= 1 (length done.tools)) (= "completed" (. done :tools 1 :status)))
         done))

;; <CR> in a child's chat sends to the child, not the parent
(let [count parent.turns-finished]
  (vim.api.nvim_buf_set_lines child.buf -2 -1 false ["plain"])
  (vim.api.nvim_win_set_cursor 0 [(vim.api.nvim_buf_line_count child.buf) 0])
  (vim.cmd "stopinsert")
  (vim.api.nvim_feedkeys (vim.keycode "<CR>") :x false)
  (wait #(= 4 child.turns-finished))
  (check "<CR> in a child's chat sends to the child"
         (and (= 4 child.turns-finished) (= count parent.turns-finished))
         child.turns-finished))

(vim.api.nvim_win_close 0 true)
(vim.api.nvim_set_current_buf parent.buf)

;; Waiting and cancelling -----------------------------------------------------------

(call-tool "agent_send" {:id "opencode-1" :prompt "stall"})
(let [still (call-tool "agent_wait" {:id "opencode-1" :timeout 1})]
  (check "agent_wait gives up in time and says so"
         (and (= "running" still.state) (= true still.timed_out)) still)
  (check "and shows the tool still running"
         (vim.tbl_contains still.running_tools "Task explore: find the parser") still))
(let [now (call-tool "agent_status" {:id "opencode-1"})]
  (check "agent_status shows a running child" (= "running" now.state) now))
(check "the statusline counts it"
       (not= nil (string.find (session.status-text) "1 agent" 1 true))
       (session.status-text))
(let [(_ problem) (call-tool "agent_send" {:id "opencode-1" :prompt "plain"})]
  (check "a running child takes no prompts" (not= nil (string.find problem "running" 1 true)) problem))
(call-tool "agent_cancel" {:id "opencode-1"})
(let [done (call-tool "agent_wait" {:id "opencode-1"})]
  (check "agent_cancel ends the turn, and the session stays"
         (and (= "idle" done.state) (= "cancelled" done.stop_reason)) done))

;; Children that go wrong -----------------------------------------------------------

(let [bad (call-tool "agent_start" {:agent "broken" :prompt "plain"})]
  (check "an agent that can't start says failed, with why"
         (and (= "failed" bad.state) (not= nil (string.find bad.error "could not start" 1 true))) bad)
  (let [done (call-tool "agent_wait" {:id bad.id})]
    (check "and agent_wait doesn't hang on it" (= "failed" done.state) done)))

(call-tool "agent_start" {:agent "opencode" :prompt "die"})
(let [done (call-tool "agent_wait" {:id "opencode-3"})]
  (check "an agent that dies mid-turn says exited, with the reason"
         (and (= "exited" done.state)
              (not= nil (string.find done.stop_reason "exited with code 3" 1 true)))
         done))

(let [fresh (call-tool "agent_start" {:agent "extra" :prompt "plain"})]
  (call-tool "agent_wait" {:id fresh.id})
  (check "a child's settings don't replace what :Acp completes"
         (= nil (string.find (table.concat (vim.fn.readfile vim.g.acp-config-cache) "") "speed" 1 true)))
  (call-tool "agent_stop" {:id fresh.id}))

(let [fresh (call-tool "agent_start" {:agent "opencode" :prompt "plain" :model "sonnet"})]
  (call-tool "agent_wait" {:id fresh.id})
  (let [now (call-tool "agent_status" {:id fresh.id})]
    (check "agent_start can choose the model" (= "Sonnet 5.5" now.model) now))
  (call-tool "agent_stop" {:id fresh.id}))

;; Stopping and limits --------------------------------------------------------------

(let [stopped (call-tool "agent_stop" {:id "opencode-1"})]
  (check "agent_stop ends the session" (= "stopped" stopped.state) stopped)
  (check "its chat closes" (not (vim.api.nvim_buf_is_valid child.buf)))
  (check "its result can still be asked for"
         (= "cancelled" (. (call-tool "agent_result" {:id "opencode-1"}) :stop_reason))))

(set vim.g.acp-delegate-max 1)
(call-tool "agent_start" {:agent "opencode" :prompt "stall"})
(let [(_ problem) (call-tool "agent_start" {:agent "opencode" :prompt "plain"})]
  (check "the number of running agents is capped"
         (not= nil (string.find problem "already running" 1 true)) problem))
(set vim.g.acp-delegate-max nil)

;; An agent with no MCP over HTTP is told so, and carries on
(vim.cmd "Acp! nomcp")
(local without (session.current))
(wait #without.ready)
(check "stopping a parent stops its children"
       (= 0 (length (vim.tbl_filter #(not $1.ended) (session.children parent)))))
(check "and takes the server down" (= 0 (. (http server-url {:body "{}"}) :status)))
(check "an agent that can't take the tools says so, and still starts"
       (has-line (lines-of without.buf) "takes no MCP servers over HTTP"))
(vim.cmd "AcpStop")

;; egress_status --------------------------------------------------------------------
;; A sandboxed session with no :delegate: the proxy is left out, as its answers are
;; covered in acp_test, and the question comes in as the proxy's would.

(let [box {:prefix [] :env {} :net :proxy :allow [] :log (vim.fn.tempname)
           :partial "" :offset 0
           :proc {:write (fn []) :kill (fn [])}}
      prepare sandbox.prepare]
  (vim.fn.writefile [] box.log)
  (set sandbox.prepare (fn [] box))
  (vim.cmd "Acp! watched")
  (set sandbox.prepare prepare)
  (let [s (session.current)
        egress-tool #(call-tool "egress_status" $1)
        answer (fn [host choice]
                 (let [row (accumulate [at nil i l (ipairs (lines-of s.buf)) &until at]
                             (when (string.find l (.. "> egress: " host) 1 true) i))]
                   (session.choose-egress-at s (+ row choice))))
        host-of (fn [reply host]
                  (accumulate [found nil _ h (ipairs reply.hosts) &until found]
                    (when (= h.host host) h)))]
    (wait #s.ready)
    (let [server (. s.mcp-servers 1)]
      (set server-url server.url)
      (set server-token (string.match (. server :headers 1 :value) "Bearer (.+)")))
    (let [init (rpc "initialize" {:protocolVersion "2025-06-18"})
          names (vim.tbl_map #$1.name (. (rpc "tools/list") :result :tools))]
      (check "a sandboxed session without :delegate gets egress_status and nothing else"
             (vim.deep_equal ["egress_status"] names) names)
      (check "and is told about held requests as it connects"
             (not= nil (string.find (or init.result.instructions "") "egress_status" 1 true))
             init))
    (check "a port of Neovim's own doesn't count as a host the sandbox lets out to"
           (and (= "egress to a.example:443" (sandbox.describe s.agent.sandbox))
                (= "no host allowed"
                   (sandbox.describe (sandbox.forward {:net :proxy} 4242))))
           (sandbox.describe s.agent.sandbox))
    (let [reply (egress-tool)]
      (check "with nothing held it answers at once, and says the cause is elsewhere"
             (and (= 0 (length reply.hosts)) reply.note (= false reply.timed_out))
             reply))
    (box.on-ask "held.example:443")
    (let [reply (egress-tool {:timeout 1})
          host (host-of reply "held.example:443")]
      (check "a pending host holds the call until the time is up, and says to wait again"
             (and reply.timed_out (= "pending" host.state)
                  (not= nil (string.find host.next "keep waiting" 1 true)))
             reply))
    (vim.defer_fn #(answer "held.example:443" 1) 300)
    (let [started (vim.uv.now)
          reply (egress-tool {:timeout 20})
          host (host-of reply "held.example:443")]
      (check "the answer ends the wait early, and says to retry"
             (and (= false reply.timed_out) (= "allowed" host.state)
                  (< (- (vim.uv.now) started) 10000)
                  (not= nil (string.find host.next "Retry" 1 true)))
             reply))
    (box.on-ask "no.example:443")
    (vim.defer_fn #(answer "no.example:443" 2) 300)
    (let [host (host-of (egress-tool {:timeout 20}) "no.example:443")]
      (check "a refusal says not to go round it"
             (and (= "denied" host.state)
                  (not= nil (string.find host.next "another way" 1 true)))
             host))
    (box.on-ask "away.example:443")
    (set vim.g.acp-egress-wait-seconds 1)
    (vim.wait 1100)
    (let [started (vim.uv.now)
          reply (egress-tool {:timeout 20})
          host (host-of reply "away.example:443")]
      (check "a host waiting too long doesn't hold the call, and says to stop waiting"
             (and (= false reply.timed_out) (= "pending" host.state)
                  (< (- (vim.uv.now) started) 5000)
                  (not= nil (string.find host.next "Stop waiting" 1 true)))
             reply))
    (set vim.g.acp-egress-wait-seconds nil)
    (let [reply (call-tool "egress_status" {:timeout 1})]
      (check "no tool answers: the question is still open after all this"
             (= "pending" (. (host-of reply "away.example:443") :state))
             reply))
    (vim.cmd "AcpStop")
    (vim.fn.delete box.log)))

(check "protocol.http-mcp-server carries the token as a header"
       (= "Bearer t" (. (protocol.http-mcp-server "n" "u" "t") :headers 1 :value)))

(vim.fn.delete vim.g.acp-log-dir "rf")
(vim.fn.delete vim.g.acp-debug-log)
(vim.fn.delete vim.g.acp-config-cache)
(vim.fn.delete vim.g.acp-egress-log-dir "rf")
(out (if (= 0 (length failures)) "all passed" (.. (length failures) " failed")))
(vim.cmd (if (= 0 (length failures)) "qa!" "cquit!"))
