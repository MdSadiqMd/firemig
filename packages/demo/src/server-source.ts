export const counterServerSource = String.raw`#!/usr/bin/env python3
import json
import os
import socketserver
import threading
import time

boot_id = open("/proc/sys/kernel/random/boot_id", encoding="utf-8").read().strip()
pid = os.getpid()
counter = 0
target = 50
events = []
last_acked = 0
condition = threading.Condition()

def tick():
    global counter
    while counter < target:
        time.sleep(0.25)
        with condition:
            counter += 1
            events.append({
                "seq": counter,
                "boot_id": boot_id,
                "pid": pid,
                "counter": counter,
                "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            })
            condition.notify_all()

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        global last_acked
        reader = self.request.makefile("rb")
        while last_acked < target:
            with condition:
                condition.wait_for(lambda: len(events) > last_acked)
                event = events[last_acked]
            self.request.sendall((json.dumps(event, separators=(",", ":")) + "\n").encode())
            acknowledgement = reader.readline().decode("utf-8", errors="replace").strip()
            if acknowledgement != f"ACK {event['seq']}":
                return
            with condition:
                if event["seq"] == last_acked + 1:
                    last_acked = event["seq"]
                    condition.notify_all()

threading.Thread(target=tick, daemon=True).start()
with socketserver.ThreadingTCPServer(("0.0.0.0", 8080), Handler) as server:
    server.daemon_threads = True
    server.serve_forever()
`;
