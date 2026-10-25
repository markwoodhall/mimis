"""A scripted ACP v1 agent for testing the Neovim client. The prompt text picks the scenario."""
import json, os, sys, time

# An optional argument names this instance (python3 fake_agent.py opencode), and the
# version says whether the client let ANTHROPIC_API_KEY through, so tests can tell
# agents and their environments apart.
NAME = "fake" + (" " + sys.argv[1] if len(sys.argv) > 1 else "")
VERSION = "key" if "ANTHROPIC_API_KEY" in os.environ else "no-key"

SID = "sess-1"
RESUMABLE = len(sys.argv) > 1 and sys.argv[1] == "resumable"
HERE = os.getcwd()
# Earlier sessions the "resumable" instance can list and load: id -> (cwd, title, updated at).
OLD = {
    "old-1": (HERE, "First chat", "2026-10-01T09:00:00Z"),
    "old-2": (HERE, "Second chat\nwith a second line", "2026-10-02T09:00:00Z"),
    "old-3": (HERE, None, "2026-10-03T09:00:00Z"),
    "other-1": (os.environ.get("FAKE_OTHER_CWD", "/tmp/elsewhere"), "Other project", "2026-10-04T09:00:00Z"),
}
config = {"mode": "default", "model": "default"}


def send(msg):
    msg["jsonrpc"] = "2.0"
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def update(u):
    send({"method": "session/update", "params": {"sessionId": SID, "update": u}})


def text(t):
    update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": t}})


def user(t):
    update({"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": t}})


def thought(t):
    update({"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": t}})


def replay(session_id):
    user("hel")
    user("lo there")
    thought("pondering")
    text("Hi ")
    text("there.")
    update({"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read /tmp/x/a.txt", "kind": "read",
            "status": "pending"})
    update({"sessionUpdate": "tool_call_update", "toolCallId": "r1", "status": "completed",
            "rawOutput": "contents"})
    user("second question")
    text("Second answer.")
    update({"sessionUpdate": "usage_update", "used": 5000, "size": 100000})
    update({"sessionUpdate": "config_option_update", "configOptions": config_options()})


def config_options():
    return [
        {"id": "mode", "name": "Mode", "category": "mode", "type": "select",
         "currentValue": config["mode"],
         "options": [{"value": "default", "name": "Manual"},
                     {"value": "plan", "name": "Plan", "description": "Plan first"}]},
        {"id": "model", "name": "Model", "category": "model", "type": "select",
         "currentValue": config["model"],
         "options": [{"group": "main", "name": "Main",
                      "options": [{"value": "default", "name": "Default (recommended)", "description": "Opus 5.5"},
                                  {"value": "sonnet", "name": "Sonnet 5.5"}]}]},
        # boolean options need a client capability the client doesn't declare: must be ignored
        {"id": "brave", "name": "Brave", "type": "boolean", "currentValue": True},
    ]


pending_prompt = None
for line in sys.stdin:
    msg = json.loads(line)
    m = msg.get("method")
    if m == "initialize":
        assert msg["params"]["protocolVersion"] == 1
        send({"id": msg["id"], "result": {"protocolVersion": 1, "agentCapabilities":
                                          dict({"loadSession": RESUMABLE},
                                               **({"sessionCapabilities": {"list": {}}} if RESUMABLE else {})),
                                          "authMethods": [], "agentInfo": {"name": NAME, "version": VERSION}}})
    elif m == "session/new":
        assert msg["params"]["mcpServers"] == []
        send({"id": msg["id"], "result": {"sessionId": SID, "configOptions": config_options()}})
        update({"sessionUpdate": "available_commands_update", "availableCommands": []})
    elif m == "session/list":
        p = msg["params"]
        found = [{"sessionId": i, "cwd": c, "title": t, "updatedAt": u}
                 for i, (c, t, u) in OLD.items() if "cwd" not in p or p["cwd"] == c]
        start = int(p.get("cursor") or 0)
        page = found[start:start + 2]
        result = {"sessions": [{k: v for k, v in x.items() if v is not None} for x in page]}
        if start + 2 < len(found):
            result["nextCursor"] = str(start + 2)
        send({"id": msg["id"], "result": result})
    elif m == "session/load":
        p = msg["params"]
        assert p["mcpServers"] == []
        if p["sessionId"] not in OLD:
            send({"id": msg["id"], "error": {"code": -32602, "message": "session not found"}})
            continue
        SID = p["sessionId"]
        replay(SID)
        send({"id": msg["id"], "result": {"configOptions": config_options()}})
    elif m == "session/set_config_option":
        p = msg["params"]
        config[p["configId"]] = p["value"]
        send({"id": msg["id"], "result": {"configOptions": config_options()}})
    elif m == "session/prompt":
        pending_prompt = msg["id"]
        prompt = msg["params"]["prompt"][0]["text"]
        update({"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "hmm\nlet me "}})
        update({"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "think"}})
        update({"sessionUpdate": "usage_update", "used": 25000, "size": 100000})
        if prompt == "slow":
            text("Working on it")
            send({"id": 102, "method": "session/request_permission",
                  "params": {"sessionId": SID, "toolCall": {"toolCallId": "t9", "title": "Run `rm -rf build`"},
                             "options": [{"optionId": "allow", "name": "Allow once", "kind": "allow_once"}]}})
            continue
        if prompt == "plain":
            text("Plain reply.")
            send({"id": pending_prompt, "result": {"stopReason": "end_turn"}})
            continue
        if prompt == "long titles":
            long = "cd /tmp/x && " + " && ".join("echo step-%d" % i for i in range(20))
            update({"sessionUpdate": "tool_call", "toolCallId": "long1", "title": long, "kind": "execute", "status": "completed"})
            update({"sessionUpdate": "tool_call", "toolCallId": "long2", "title": "cd /tmp/x && \\\n  make test",
                    "kind": "execute", "status": "completed"})
            update({"sessionUpdate": "tool_call", "toolCallId": "short", "title": "ls", "kind": "execute", "status": "completed"})
            send({"id": pending_prompt, "result": {"stopReason": "end_turn"}})
            continue
        if prompt in ("long command", "big edit"):
            if prompt == "long command":
                tool = {"toolCallId": "long3", "kind": "execute",
                        "title": "cd /tmp/x && " + " && ".join("echo step-%d" % i for i in range(20))}
            else:
                tool = {"toolCallId": "big1", "kind": "edit", "title": "Write big.txt",
                        "content": [{"type": "diff", "path": "/tmp/x/big.txt", "oldText": "",
                                     "newText": "\n".join("line %d" % i for i in range(200))}]}
            update(dict(tool, sessionUpdate="tool_call", status="pending"))
            send({"id": 103, "method": "session/request_permission",
                  "params": {"sessionId": SID, "toolCall": tool,
                             "options": [{"optionId": "allow-once", "name": "Yes", "kind": "allow_once"},
                                         {"optionId": "reject-once", "name": "No", "kind": "reject_once"}]}})
            pending_tool = tool["toolCallId"]
            continue
        if prompt == "leave plan":
            config["mode"] = "default"
            update({"sessionUpdate": "config_option_update", "configOptions": config_options()})
            text("Plan done.")
            send({"id": pending_prompt, "result": {"stopReason": "end_turn"}})
            continue
        # default scenario: a JSON line split across writes, tools, an unknown request, a permission
        raw = json.dumps({"jsonrpc": "2.0", "method": "session/update",
                          "params": {"sessionId": SID, "update": {"sessionUpdate": "agent_message_chunk",
                                                                  "content": {"type": "text", "text": "You said: "}}}}) + "\n"
        sys.stdout.write(raw[:20]); sys.stdout.flush(); time.sleep(0.05)
        sys.stdout.write(raw[20:]); sys.stdout.flush()
        text(prompt + "\n\nLet me look.")
        update({"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "Read /tmp/x/file.clj", "kind": "read", "status": "pending"})
        update({"sessionUpdate": "tool_call", "toolCallId": "t2", "title": "Edit file.clj", "kind": "edit", "status": "pending"})
        update({"sessionUpdate": "tool_call_update", "toolCallId": "t1", "rawInput": {"file_path": "/tmp/x/file.clj"}})
        update({"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
                "rawOutput": "\u001b[01;34m(ns x)\u001b[0m\n(def a 1)"})
        update({"sessionUpdate": "tool_call_update", "toolCallId": "t2",
                "locations": [{"path": "/tmp/x/file.clj", "line": 2}],
                "rawInput": {"file_path": "/tmp/x/file.clj", "old_string": "(def a 1)", "new_string": "(def a 2)"},
                "content": [{"type": "diff", "path": "/tmp/x/file.clj",
                             "oldText": "(ns x)\n(def a 1)", "newText": "(ns x)\n(def a 2)"}]})
        send({"id": 100, "method": "fs/unknown_thing", "params": {}})
        send({"id": 101, "method": "session/request_permission",
              "params": {"sessionId": SID,
                         "toolCall": {"toolCallId": "t2", "title": "Edit file.clj", "kind": "edit",
                                      "content": [{"type": "diff", "path": "/tmp/x/file.clj",
                                                   "oldText": "(ns x)\n(def a 1)", "newText": "(ns x)\n(def a 2)"}]},
                         "options": [{"optionId": "allow", "name": "Allow once", "kind": "allow_once"},
                                     {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]}})
    elif msg.get("id") == 103:
        allowed = msg["result"]["outcome"].get("optionId") == "allow-once"
        update({"sessionUpdate": "tool_call_update", "toolCallId": pending_tool,
                "status": "completed" if allowed else "failed"})
        send({"id": pending_prompt, "result": {"stopReason": "end_turn"}})
    elif m == "session/cancel":
        send({"id": pending_prompt, "result": {"stopReason": "cancelled"}})
    elif msg.get("id") == 101:
        allowed = msg["result"]["outcome"].get("optionId") == "allow"
        update({"sessionUpdate": "tool_call_update", "toolCallId": "t2", "status": "completed" if allowed else "failed",
                "rawOutput": "The file /tmp/x/file.clj has been updated."})
        text("Done:\n\n```clojure\n(+ 1 2)\n```\n")
        send({"id": pending_prompt, "result": {"stopReason": "end_turn"}})
    elif msg.get("id") == 100:
        assert msg["error"]["code"] == -32601
