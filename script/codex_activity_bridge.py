# SPDX-License-Identifier: GPL-3.0-only

"""Read-only projection of Codex Desktop's private IPC runtime status.

The Unix socket remains private to this user. The loopback endpoint publishes
only an aggregate phase, count and freshness timestamp. Conversation snapshots
are discarded immediately after extracting runtime status; no text is logged.
"""

import datetime
import http.server
import json
import os
from pathlib import Path
import re
import select
import socket
import stat
import struct
import subprocess
import threading
import time
import uuid


PORT = 48731
CODEX_STATE_ROOT = Path.home() / ".codex"
SOCKET_PATH = CODEX_STATE_ROOT / "ipc" / "ipc.sock"
STREAM_VERSION = 11
MAX_FRAME_BYTES = 256 * 1024 * 1024
THREAD_ID = re.compile(r"([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\.jsonl$")
STATUS_TYPES = {"active", "idle", "notLoaded", "systemError"}
WAIT_FLAGS = {"waitingOnApproval", "waitingOnUserInput"}


def clean_status(value):
    if not isinstance(value, dict) or value.get("type") not in STATUS_TYPES:
        return None
    status_type = value["type"]
    flags = value.get("activeFlags", [])
    if not isinstance(flags, list) or any(not isinstance(flag, str) or flag not in WAIT_FLAGS for flag in flags):
        return None
    return {"type": status_type, "activeFlags": list(flags)}


class ActivityProjection:
    """Retains metadata only; every unknown state freezes the avatar."""

    def __init__(self):
        self.connected = False
        self.threads = {}

    def disconnect(self):
        self.connected = False
        self.threads.clear()

    def consume(self, message, now):
        """Return a thread id when a revision gap needs a fresh snapshot."""
        if message.get("type") != "broadcast":
            return None
        method = message.get("method")
        params = message.get("params", {})
        if method == "client-status-changed" and params.get("status") == "disconnected":
            owner = params.get("clientId")
            self.threads = {key: state for key, state in self.threads.items()
                            if state["owner"] != owner}
            return None
        if method == "ipc-connection-reset":
            self.disconnect()
            return None
        if method != "thread-stream-state-changed" or params.get("hostId") != "local":
            return None
        thread_id = params.get("conversationId")
        if not isinstance(thread_id, str):
            return None
        if message.get("version") != STREAM_VERSION:
            self.threads.pop(thread_id, None)
            return None
        change = params.get("change", {})
        owner = message.get("sourceClientId")
        revision = change.get("revision")
        if not isinstance(revision, int) or not isinstance(owner, str):
            self.threads.pop(thread_id, None)
            return None
        if change.get("type") == "snapshot":
            status = clean_status(change.get("conversationState", {}).get("threadRuntimeStatus"))
            if status is None:
                self.threads.pop(thread_id, None)
            else:
                self.threads[thread_id] = {"status": status, "revision": revision,
                                           "owner": owner, "seen": now}
            return None
        if change.get("type") != "patches":
            return None
        current = self.threads.get(thread_id)
        if current is None or current["owner"] != owner or current["revision"] != change.get("baseRevision"):
            self.threads.pop(thread_id, None)
            return thread_id
        status = dict(current["status"])
        for patch in change.get("patches", []):
            path = patch.get("path", [])
            if not isinstance(path, list) or not path or path[0] != "threadRuntimeStatus":
                continue
            if len(path) == 1:
                status = clean_status(patch.get("value"))
            elif len(path) == 2 and path[1] in ("type", "activeFlags") and status is not None:
                status[path[1]] = patch.get("value")
            else:
                self.threads.pop(thread_id, None)
                return thread_id
        status = clean_status(status)
        if status is None:
            self.threads.pop(thread_id, None)
            return thread_id
        current.update(status=status, revision=revision, seen=now)
        return None

    def summary(self, now):
        fresh = [state["status"] for state in self.threads.values() if now - state["seen"] <= 45]
        active = [state for state in fresh if state["type"] == "active"]
        working = [state for state in active if not state["activeFlags"]]
        if not self.connected or (self.threads and not fresh) or not self.threads:
            phase = "offline"
        elif working:
            phase = "active"
        elif active:
            phase = "waiting"
        elif any(state["type"] == "systemError" for state in fresh):
            phase = "error"
        else:
            phase = "idle"
        return {"service": "boringnotch-codex-activity", "version": 1,
                "phase": phase, "activeCount": len(active), "updatedAt": now}


def desktop_server_identity():
    """Only the server parented by Desktop qualifies; unrelated CLI servers do not."""
    result = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,lstart=,comm="],
                            capture_output=True, text=True, check=True,
                            env={**os.environ, "LC_ALL": "C"}, timeout=3)
    processes = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 7)
        if len(fields) == 8:
            processes[int(fields[0])] = (int(fields[1]), " ".join(fields[2:7]), fields[7])
    for pid, (parent, started, command) in processes.items():
        parent_command = processes.get(parent, (None, None, ""))[2]
        if command.endswith(".app/Contents/Resources/codex") and parent_command.endswith(".app/Contents/MacOS/ChatGPT"):
            timestamp = datetime.datetime.strptime(started, "%a %b %d %H:%M:%S %Y").timestamp()
            return pid, timestamp
    return None


def discover_threads(started_at):
    """Read directory entries and mtimes, never transcript contents."""
    result = {}
    for path in (CODEX_STATE_ROOT / "sessions").rglob("rollout-*.jsonl"):
        match = THREAD_ID.search(path.name)
        if match:
            try:
                modified = path.stat().st_mtime
                if modified >= started_at:
                    result[match.group(1)] = modified
            except OSError:
                pass
    return result


class DesktopObserver:
    def __init__(self):
        self.projection = ActivityProjection()
        self.lock = threading.Lock()
        self.last_poll = 0
        self.sock = None
        self.client_id = None
        self.pending = bytearray()
        self.subscribed = {}

    def snapshot(self):
        with self.lock:
            now = time.time()
            if now - self.last_poll > 8:
                return {"service": "boringnotch-codex-activity", "version": 1,
                        "phase": "offline", "activeCount": 0, "updatedAt": now}
            return self.projection.summary(now)

    def send(self, message):
        data = json.dumps(message, separators=(",", ":")).encode()
        self.sock.sendall(struct.pack("<I", len(data)) + data)

    def follow(self, thread_id, now):
        self.send({"type": "broadcast", "sourceClientId": self.client_id,
                   "method": "thread-stream-following-changed", "version": 1,
                   "params": {"hostId": "local", "conversationId": thread_id, "following": True}})
        self.subscribed[thread_id] = now

    def connect(self):
        entry = SOCKET_PATH.lstat()
        directory = SOCKET_PATH.parent.stat()
        if not stat.S_ISSOCK(entry.st_mode) or entry.st_uid != os.getuid() or directory.st_uid != os.getuid() or directory.st_mode & 0o022:
            raise OSError("Unsafe IPC ownership")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(2)
        self.sock.connect(str(SOCKET_PATH))
        self.send({"type": "request", "requestId": str(uuid.uuid4()), "method": "initialize",
                   "version": 0, "params": {"clientType": "boringNotch-activity-observer"}})

    def receive(self, now):
        if not select.select([self.sock], [], [], 0.2)[0]:
            return
        chunk = self.sock.recv(65536)
        if not chunk:
            raise EOFError()
        self.pending.extend(chunk)
        while len(self.pending) >= 4:
            size = struct.unpack_from("<I", self.pending)[0]
            if size == 0 or size > MAX_FRAME_BYTES:
                raise ValueError("Invalid IPC frame length")
            if len(self.pending) < 4 + size:
                return
            message = json.loads(self.pending[4:4 + size])
            del self.pending[:4 + size]
            if message.get("type") == "response" and message.get("method") == "initialize":
                self.client_id = message.get("result", {}).get("clientId")
                with self.lock:
                    self.projection.connected = bool(self.client_id)
            elif message.get("type") == "client-discovery-request":
                self.send({"type": "client-discovery-response", "requestId": message["requestId"],
                           "response": {"canHandle": False}})
            else:
                if message.get("method") == "ipc-connection-reset":
                    raise ConnectionResetError()
                if message.get("method") == "client-status-changed":
                    # New owners must get a fresh subscription after a window reconnects.
                    self.subscribed.clear()
                with self.lock:
                    retry = self.projection.consume(message, now)
                if retry:
                    self.follow(retry, now)
            # The full frame ends its life here. Only runtime status survives.
            del message

    def reset(self):
        if self.sock:
            self.sock.close()
        self.sock = None
        self.client_id = None
        self.pending.clear()
        self.subscribed.clear()
        with self.lock:
            self.projection.disconnect()

    def run(self):
        identity = None
        checked_at = 0
        discovered_at = 0
        last_status = None
        last_error = None
        while True:
            try:
                now = time.time()
                if now - checked_at >= 2:
                    current = desktop_server_identity()
                    checked_at = now
                    if current != identity:
                        self.reset()
                        identity = current
                        discovered_at = 0
                with self.lock:
                    self.last_poll = now
                if identity is None:
                    time.sleep(1)
                    continue
                if self.sock is None:
                    self.connect()
                self.receive(now)
                status = self.snapshot()
                display_status = (status["phase"], status["activeCount"])
                if display_status != last_status:
                    print(f"Codex activity: {display_status[0]}, active tasks: {display_status[1]}", flush=True)
                    last_status = display_status
                last_error = None
                if self.client_id and now - discovered_at >= 3:
                    discovered_at = now
                    candidates = discover_threads(identity[1])
                    with self.lock:
                        states = {key: state["seen"] for key, state in self.projection.threads.items()}
                    for thread_id in candidates:
                        last_sent = self.subscribed.get(thread_id, 0)
                        last_seen = states.get(thread_id, 0)
                        if not last_sent or now - max(last_sent, last_seen) >= 30:
                            self.follow(thread_id, now)
            except (OSError, ValueError, EOFError, subprocess.SubprocessError) as error:
                self.reset()
                error_type = type(error).__name__
                if error_type != last_error:
                    print(f"Codex activity source disconnected ({error_type}); retrying", flush=True)
                    last_error = error_type
                time.sleep(2)


def main():
    observer = DesktopObserver()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/activity" or self.headers.get("Origin") or self.headers.get("Host") != f"127.0.0.1:{PORT}":
                self.send_error(404)
                return
            data = json.dumps(observer.snapshot(), separators=(",", ":")).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=observer.run, name="codex-desktop-observer", daemon=True).start()
    print(f"Codex Desktop activity projection listening on 127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    finally:
        observer.reset()
        server.server_close()


if __name__ == "__main__":
    main()
