#!/usr/bin/env python3
import base64
import json
import os
import pathlib
import socket
import subprocess
import time
import traceback

PORT = 5000
MAX_REQUEST_BYTES = 16 * 1024 * 1024
BACKGROUND_PROCESSES = {}


def boot_id():
    return pathlib.Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def ready(_params):
    return {"bootId": boot_id()}


def write_file(params):
    path = pathlib.Path(params["path"])
    content = base64.b64decode(params["contentBase64"], validate=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.firemig-{os.getpid()}")
    with temporary.open("wb") as file:
        file.write(content)
        file.flush()
        os.fsync(file.fileno())
    if "mode" in params:
        temporary.chmod(int(params["mode"]))
    temporary.replace(path)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return {"path": str(path), "bytes": len(content)}


def command_environment(params):
    environment = os.environ.copy()
    for key, value in params.get("env", {}).items():
        environment[str(key)] = str(value)
    return environment


def run_command(params):
    command = params["command"]
    cwd = params.get("cwd", "/")
    environment = command_environment(params)
    started = time.monotonic_ns()
    if params.get("background", False):
        process = subprocess.Popen(
            ["/bin/sh", "-lc", command],
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        BACKGROUND_PROCESSES[process.pid] = process
        return {"commandId": str(process.pid), "pid": process.pid}

    timeout = params.get("timeoutMs")
    completed = subprocess.run(
        ["/bin/sh", "-lc", command],
        cwd=cwd,
        env=environment,
        capture_output=True,
        timeout=None if timeout is None else float(timeout) / 1000,
        check=False,
    )
    duration_ms = (time.monotonic_ns() - started) // 1_000_000
    return {
        "commandId": f"fg-{started}",
        "exitCode": completed.returncode,
        "stdout": completed.stdout.decode("utf-8", errors="replace"),
        "stderr": completed.stderr.decode("utf-8", errors="replace"),
        "durationMs": duration_ms,
    }


def stat_path(params):
    value = pathlib.Path(params["path"]).stat()
    return {
        "size": value.st_size,
        "mode": value.st_mode & 0o7777,
        "mtimeNs": value.st_mtime_ns,
        "isFile": pathlib.Path(params["path"]).is_file(),
        "isDirectory": pathlib.Path(params["path"]).is_dir(),
    }


def probe(_params):
    memory = {}
    for line in pathlib.Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        memory[key] = int(value.strip().split()[0])
    load_average = pathlib.Path("/proc/loadavg").read_text().split()[0]
    return {
        "dirtyKiB": memory.get("Dirty", 0),
        "writebackKiB": memory.get("Writeback", 0),
        "loadavg1": float(load_average),
    }


def sync_clock(params):
    unix_time_ns = params.get("unixTimeNs")
    if not isinstance(unix_time_ns, (int, float)) or unix_time_ns <= 0:
        raise ValueError("unixTimeNs must be a positive number")
    time.clock_settime(time.CLOCK_REALTIME, float(unix_time_ns) / 1_000_000_000)
    return {"synced": True}


def health(params):
    pid = params.get("pid")
    process_alive = pid is None or pathlib.Path(f"/proc/{int(pid)}").exists()
    return {"bootId": boot_id(), "pid": pid, "processAlive": process_alive}


def fsfreeze(params):
    action = "--unfreeze" if params.get("unfreeze", False) else "--freeze"
    mountpoint = params.get("mountpoint", "/")
    subprocess.run(["fsfreeze", action, mountpoint], check=True)
    return {"frozen": action == "--freeze"}


METHODS = {
    "ready": ready,
    "write_file": write_file,
    "run_command": run_command,
    "stat": stat_path,
    "probe": probe,
    "sync_clock": sync_clock,
    "health": health,
    "fsfreeze": fsfreeze,
}


def read_request(connection):
    chunks = bytearray()
    while len(chunks) <= MAX_REQUEST_BYTES:
        chunk = connection.recv(65536)
        if not chunk:
            raise ConnectionError("connection closed before request")
        chunks.extend(chunk)
        newline = chunks.find(b"\n")
        if newline >= 0:
            return json.loads(chunks[:newline].decode("utf-8"))
    raise ValueError("request exceeds maximum size")


def handle(connection):
    request_id = None
    try:
        request = read_request(connection)
        request_id = request.get("id")
        method = METHODS.get(request.get("method"))
        if method is None:
            raise ValueError(f"unknown method: {request.get('method')}")
        response = {"id": request_id, "ok": True, "result": method(request.get("params", {}))}
    except Exception as error:
        traceback.print_exc()
        response = {
            "id": request_id,
            "ok": False,
            "error": {"code": "GUEST_AGENT_ERROR", "message": str(error)},
        }
    connection.sendall(json.dumps(response, separators=(",", ":")).encode("utf-8") + b"\n")


def serve():
    if not hasattr(socket, "AF_VSOCK"):
        raise RuntimeError("Python was built without AF_VSOCK support")
    listener = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((socket.VMADDR_CID_ANY, PORT))
    listener.listen(128)
    while True:
        connection, _address = listener.accept()
        with connection:
            handle(connection)


if __name__ == "__main__":
    serve()
