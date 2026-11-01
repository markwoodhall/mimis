#!/usr/bin/env python3
"""Egress proxy and in-sandbox relay for the ACP client.

Two roles, run in two network namespaces:

  serve   the host side. A CONNECT proxy on a unix socket. Only the hosts on
          --allow may be reached; every attempt, allowed or denied, is logged.
          With --ask N, a host not on the list is held for up to N seconds and
          asked about on stdout ("ASK host:port"); Neovim answers on stdin with
          "allow", "deny" or "block" and the host. Allow and block last as long
          as the proxy. The sandbox can reach the socket but not these pipes, so
          the agent can't answer for you.
  relay   the sandbox side. Bridges 127.0.0.1:<port> inside the sandbox to that
          unix socket, then execs the agent, so the agent's pid is bwrap's child
          and the agent inherits the proxy's lifetime. Each --forward PORT also
          listens on 127.0.0.1:PORT inside the sandbox and asks the proxy for
          localhost:PORT on the host, so a client that knows nothing of proxies
          (psql, redis-cli) reaches a host service once you allow it.

The network namespace has no route out, so the proxy is the only way to reach
anything: an agent that ignores HTTPS_PROXY does not leak, it fails.
"""
import argparse
import ctypes
import os
import select
import signal
import socket
import subprocess
import sys
import threading
import time

PR_SET_PDEATHSIG = 1
IDLE = 120.0


def log(path, line):
    if not path:
        return
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    try:
        with open(path, "a") as f:
            f.write(f"{stamp} {line}\n")
    except OSError:
        pass


def split_hostport(text, default_port=443):
    text = text.strip()
    if text.startswith("["):
        host, _, rest = text[1:].partition("]")
        port = rest[1:] if rest.startswith(":") else ""
        return host, port or str(default_port)
    host, _, port = text.rpartition(":")
    if not host:
        return text, str(default_port)
    return host, port or str(default_port)


def pump(a, b):
    try:
        while True:
            readable, _, _ = select.select([a, b], [], [], IDLE)
            if not readable:
                return
            for s in readable:
                data = s.recv(65536)
                if not data:
                    return
                (b if s is a else a).sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.close()
            except OSError:
                pass


class Proxy:
    def __init__(self, sock_path, allow, log_path, ask=0.0):
        self.sock_path = sock_path
        self.allow = {self.key(entry) for entry in allow}
        self.log_path = log_path
        self.ask = ask
        self.blocked = set()
        # Hosts asked about and not yet answered: one question however many
        # requests are waiting on it, and none again while it is still open.
        self.asking = set()
        self.cond = threading.Condition()

    def permitted(self, key):
        with self.cond:
            if key in self.allow:
                return True
            if not self.ask or key in self.blocked:
                return False
            if key not in self.asking:
                self.asking.add(key)
                sys.stdout.write(f"ASK {key}\n")
                sys.stdout.flush()
            self.cond.wait_for(lambda: key in self.allow or key not in self.asking,
                               self.ask)
            return key in self.allow

    def answers(self):
        # Neovim's answers. A late one still counts: the request that asked has
        # been refused by then, but the agent's next attempt gets the answer.
        for line in sys.stdin:
            parts = line.split()
            if len(parts) != 2:
                continue
            verb, key = parts[0], self.key(parts[1])
            with self.cond:
                if verb == "allow":
                    self.allow.add(key)
                elif verb == "block":
                    self.blocked.add(key)
                elif verb != "deny":
                    continue
                self.asking.discard(key)
                self.cond.notify_all()
            log(self.log_path, f"ANSWER {key} {verb}")

    @staticmethod
    def key(entry):
        host, port = split_hostport(entry)
        return f"{host.lower()}:{port}"

    def deny(self, client, key, method, detail=""):
        log(self.log_path, " ".join(x for x in ("DENY", key, method, detail) if x))
        try:
            client.sendall(b"HTTP/1.1 403 Forbidden\r\n"
                           b"Content-Length: 0\r\nConnection: close\r\n\r\n")
        except OSError:
            pass

    def handle(self, client):
        upstream = None
        try:
            client.settimeout(30)
            head = b""
            while b"\r\n\r\n" not in head and len(head) < 16384:
                chunk = client.recv(4096)
                if not chunk:
                    return
                head += chunk
            line = head.split(b"\r\n", 1)[0].decode("latin-1")
            parts = line.split()
            if len(parts) < 2:
                return self.deny(client, line or "(empty request)", "")
            method, target = parts[0], parts[1]
            if method == "CONNECT":
                key = self.key(target)
                if not self.permitted(key):
                    return self.deny(client, key, method)
                host, port = split_hostport(target)
                log(self.log_path, f"ALLOW {key} {method}")
                upstream = socket.create_connection((host, int(port)), 15)
                client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
                client.settimeout(None)
                pump(client, upstream)
                return
            if not target.lower().startswith("http://"):
                return self.deny(client, target, method, "not a proxy request")
            # Plain HTTP travels the same allowlist as a tunnel: the scheme is not the
            # thing being approved, the host is.
            rest = target[len("http://"):]
            hostport, _, path = rest.partition("/")
            host, port = split_hostport(hostport, 80)
            key = f"{host.lower()}:{port}"
            if not self.permitted(key):
                return self.deny(client, key, method, target)
            log(self.log_path, f"ALLOW {key} {method} {target}")
            upstream = socket.create_connection((host, int(port)), 15)
            version = parts[2] if len(parts) > 2 else "HTTP/1.1"
            origin = f"{method} /{path} {version}".encode("latin-1")
            upstream.sendall(head.replace(line.encode("latin-1"), origin, 1))
            client.settimeout(None)
            pump(client, upstream)
        except (OSError, ValueError) as e:
            log(self.log_path, f"ERROR {e}")
        finally:
            for s in (client, upstream):
                if s is not None:
                    try:
                        s.close()
                    except OSError:
                        pass

    def serve(self):
        # Die with Neovim: an editor that crashes should not leave a proxy (and the
        # namespace's only way out) running.
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)
        os.makedirs(os.path.dirname(self.sock_path), exist_ok=True)
        try:
            os.unlink(self.sock_path)
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.sock_path)
        os.chmod(self.sock_path, 0o600)
        server.listen(64)

        def stop(signum, _frame):
            try:
                os.unlink(self.sock_path)
            except OSError:
                pass
            sys.exit(0)

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        log(self.log_path, f"proxy {self.sock_path} allow={sorted(self.allow)}")
        if self.ask:
            threading.Thread(target=self.answers, daemon=True).start()
        while True:
            try:
                client, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=self.handle, args=(client,), daemon=True).start()


def listener(host, port):
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, int(port)))
    server.listen(64)
    return server


def tunnel(sock_path, client, port):
    # A forwarded port: CONNECT localhost:PORT through the proxy, which asks about it
    # like any other host, then carry the client's bytes. A refusal closes the client.
    upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    upstream.connect(sock_path)
    upstream.sendall(f"CONNECT localhost:{port} HTTP/1.1\r\n\r\n".encode())
    head = b""
    while b"\r\n\r\n" not in head and len(head) < 16384:
        chunk = upstream.recv(4096)
        if not chunk:
            break
        head += chunk
    status, _, rest = head.partition(b"\r\n\r\n")
    if status.split(b" ", 2)[1:2] != [b"200"]:
        upstream.close()
        client.close()
        return
    if rest:
        client.sendall(rest)
    pump(client, upstream)


def relay(sock_path, listen, forward, cmd, log_path):
    subprocess.run(["ip", "link", "set", "lo", "up"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    host, port = split_hostport(listen, 8899)
    server = listener(host, port)
    forwarded = []
    for p in forward:
        try:
            forwarded.append((listener("127.0.0.1", p), p))
        except OSError as e:
            log(log_path, f"RELAY forward {p}: {e}")

    pid = os.fork()
    if pid:  # the agent: same pid bwrap started, so closing stdin and signals behave
        server.close()
        for s, _ in forwarded:
            s.close()
        try:
            os.execvp(cmd[0], cmd)
        except OSError as e:
            log(log_path, f"RELAY exec failed: {e}")
            os._exit(127)

    # Die with the agent, or the namespace (and this socket) outlives the session.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM, 0, 0, 0)

    def one(client):
        upstream = None
        try:
            upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            upstream.connect(sock_path)
            pump(client, upstream)
        except OSError as e:
            log(log_path, f"RELAY {e}")
        finally:
            for s in (client, upstream):
                if s is not None:
                    try:
                        s.close()
                    except OSError:
                        pass

    def forwarding(srv, p):
        def handle(client):
            try:
                tunnel(sock_path, client, p)
            except OSError as e:
                log(log_path, f"RELAY forward {p}: {e}")
                client.close()

        while True:
            try:
                client, _ = srv.accept()
            except OSError:
                return
            threading.Thread(target=handle, args=(client,), daemon=True).start()

    for srv, p in forwarded:
        threading.Thread(target=forwarding, args=(srv, p), daemon=True).start()

    while True:
        try:
            client, _ = server.accept()
        except OSError:
            os._exit(0)
        threading.Thread(target=one, args=(client,), daemon=True).start()


def main():
    parser = argparse.ArgumentParser(prog="acp-egress")
    sub = parser.add_subparsers(dest="role", required=True)
    serve = sub.add_parser("serve")
    serve.add_argument("--socket", required=True)
    serve.add_argument("--allow", action="append", default=[])
    serve.add_argument("--log")
    serve.add_argument("--ask", type=float, default=0.0)
    relay_p = sub.add_parser("relay")
    relay_p.add_argument("--socket", required=True)
    relay_p.add_argument("--listen", default="127.0.0.1:8899")
    relay_p.add_argument("--log")
    relay_p.add_argument("--forward", type=int, action="append", default=[])
    relay_p.add_argument("cmd", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.role == "serve":
        Proxy(args.socket, args.allow, args.log, args.ask).serve()
    else:
        cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
        if not cmd:
            parser.error("relay needs a command after --")
        relay(args.socket, args.listen, args.forward, cmd, args.log)


if __name__ == "__main__":
    main()
