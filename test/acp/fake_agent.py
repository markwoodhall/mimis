"""A scripted ACP v1 agent for testing the Neovim client. The prompt text picks the scenario."""
import json, sys, time

SID = "sess-1"
config = {"mode": "default", "model": "default"}


def send(msg):
    msg["jsonrpc"] = "2.0"
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def update(u):
    send({"method": "session/update", "params": {"sessionId": SID, "update": u}})


def text(t):
    update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": t}})


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
        send({"id": msg["id"], "result": {"protocolVersion": 1, "agentCapabilities": {"loadSession": False},
                                          "authMethods": [], "agentInfo": {"name": "fake"}}})
    elif m == "session/new":
        assert msg["params"]["mcpServers"] == []
        send({"id": msg["id"], "result": {"sessionId": SID, "configOptions": config_options()}})
        update({"sessionUpdate": "available_commands_update", "availableCommands": []})
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
              "params": {"sessionId": SID, "toolCall": {"toolCallId": "t2", "title": "Edit file.clj"},
                         "options": [{"optionId": "allow", "name": "Allow once", "kind": "allow_once"},
                                     {"optionId": "reject", "name": "Reject", "kind": "reject_once"}]}})
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
