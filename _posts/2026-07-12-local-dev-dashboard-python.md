---
title: "A Local Dev Services Dashboard in Python"
date: 2026-07-12 10:00:00 -0700
categories: [Development, Automation]
tags: [python, dashboard, docker, development, automation]
---

A web dashboard for monitoring and controlling local development servers: service start/stop operations, status checking, and Docker Compose project management from a unified interface.

## Problem Statement

Multiple concurrent projects result in multiple development servers:

```text
Port 4000 - Jekyll blog (or 4001?)
Port 5173 - Vite project
Port 8070 - Python application
Port 8123 - Unknown service
```

This leads to multiple browser tabs, terminal windows, and frequent `lsof -i :PORT` commands to determine service locations.

## Proposed Solution

A dashboard providing consolidated visibility:

- Service running status
- Port assignments per service
- Start/stop controls
- Docker Compose project status
- Auto-refresh every 10 seconds

## Project Structure

```text
local-dashboard/
├── server.py       # Dashboard server
└── services.json   # Service definitions
```

## Configuration File

Service definitions reside in `services.json`:

```json
{
  "services": [
    {
      "name": "Blog (Jekyll)",
      "domain": "blog.lan",
      "port": 4000,
      "directory": "/home/user/projects/blog",
      "start_cmd": "bundle exec jekyll serve --future --host 0.0.0.0",
      "process_match": "jekyll serve"
    },
    {
      "name": "Frontend",
      "domain": "app.lan",
      "port": 5173,
      "directory": "/home/user/projects/frontend",
      "start_cmd": "npm run dev -- --host 0.0.0.0",
      "process_match": "vite"
    },
    {
      "name": "API Docs",
      "domain": "docs.lan",
      "port": 8080,
      "directory": "/home/user/projects/api/docs",
      "start_cmd": "python3 -m http.server 8080",
      "process_match": "http.server 8080"
    }
  ],
  "docker_compose": [
    {
      "name": "Backend Stack",
      "domain": "api.lan",
      "directory": "/home/user/projects/backend",
      "compose_file": "docker-compose.yml"
    }
  ],
  "tunnels": [
    {
      "name": "Remote Ollama",
      "domain": "ollama.lan",
      "port": 11434,
      "process_match": "ssh.*11434"
    }
  ]
}
```

Each service configuration includes:
- `name`: Display name
- `domain`: Access URL (optional)
- `port`: Listening port
- `directory`: Working directory for start command
- `start_cmd`: Service start command
- `process_match`: Regex pattern for process identification

## Dashboard Server Implementation

```python
#!/usr/bin/env python3
"""
Local Development Services Dashboard
"""

import json
import subprocess
import os
import signal
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

PORT = 9000
CONFIG_FILE = Path(__file__).parent / "services.json"


def load_config():
    with open(CONFIG_FILE) as f:
        return json.load(f)


def is_port_listening(port: int) -> bool:
    """Check if a port is listening."""
    result = subprocess.run(
        ["ss", "-tln", f"sport = :{port}"],
        capture_output=True,
        text=True
    )
    return f":{port}" in result.stdout


def find_process_by_pattern(pattern: str) -> list[dict]:
    """Find processes matching a pattern."""
    result = subprocess.run(
        ["pgrep", "-af", pattern],
        capture_output=True,
        text=True
    )
    processes = []
    for line in result.stdout.strip().split("\n"):
        if line:
            parts = line.split(" ", 1)
            if len(parts) == 2:
                processes.append({"pid": int(parts[0]), "cmd": parts[1]})
    return processes


def get_service_status(service: dict) -> dict:
    """Get status of a service."""
    port = service.get("port")
    pattern = service.get("process_match")

    status = {
        "name": service["name"],
        "domain": service.get("domain", ""),
        "port": port,
        "directory": service.get("directory", ""),
        "running": False,
        "pid": None
    }

    if port and is_port_listening(port):
        status["running"] = True

    if pattern:
        procs = find_process_by_pattern(pattern)
        if procs:
            status["running"] = True
            status["pid"] = procs[0]["pid"]

    return status


def get_docker_compose_status(dc: dict) -> dict:
    """Get status of a docker-compose project."""
    directory = dc["directory"]
    compose_file = dc.get("compose_file", "docker-compose.yml")

    result = subprocess.run(
        ["docker", "compose", "-f", compose_file, "ps", "--format", "json"],
        cwd=directory,
        capture_output=True,
        text=True
    )

    containers = []
    running_count = 0
    total_count = 0

    if result.returncode == 0 and result.stdout.strip():
        for line in result.stdout.strip().split("\n"):
            try:
                container = json.loads(line)
                containers.append({
                    "name": container.get("Name", ""),
                    "state": container.get("State", ""),
                    "status": container.get("Status", "")
                })
                total_count += 1
                if container.get("State") == "running":
                    running_count += 1
            except json.JSONDecodeError:
                pass

    return {
        "name": dc["name"],
        "domain": dc.get("domain", ""),
        "directory": directory,
        "running": running_count > 0,
        "containers": containers,
        "running_count": running_count,
        "total_count": total_count
    }


def start_service(service: dict) -> dict:
    """Start a service using nohup."""
    directory = service.get("directory")
    start_cmd = service.get("start_cmd")

    if not directory or not start_cmd:
        return {"success": False, "error": "Missing directory or start_cmd"}

    if not os.path.isdir(directory):
        return {"success": False, "error": f"Directory not found: {directory}"}

    log_file = Path(directory) / ".server.log"
    cmd = f"nohup {start_cmd} > {log_file} 2>&1 &"

    result = subprocess.run(
        cmd,
        shell=True,
        cwd=directory,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        return {"success": True, "message": f"Started {service['name']}"}
    else:
        return {"success": False, "error": result.stderr}


def stop_service(service: dict) -> dict:
    """Stop a service by killing its process."""
    pattern = service.get("process_match")
    port = service.get("port")

    killed = False

    if pattern:
        procs = find_process_by_pattern(pattern)
        for proc in procs:
            try:
                os.kill(proc["pid"], signal.SIGTERM)
                killed = True
            except ProcessLookupError:
                pass

    if not killed and port:
        result = subprocess.run(
            ["fuser", "-k", f"{port}/tcp"],
            capture_output=True
        )
        if result.returncode == 0:
            killed = True

    if killed:
        return {"success": True, "message": f"Stopped {service['name']}"}
    else:
        return {"success": False, "error": "Could not find process to stop"}


def docker_compose_action(dc: dict, action: str) -> dict:
    """Start/stop docker-compose project."""
    directory = dc["directory"]
    compose_file = dc.get("compose_file", "docker-compose.yml")

    if action == "start":
        cmd = ["docker", "compose", "-f", compose_file, "up", "-d"]
    elif action == "stop":
        cmd = ["docker", "compose", "-f", compose_file, "down"]
    else:
        return {"success": False, "error": f"Unknown action: {action}"}

    result = subprocess.run(
        cmd,
        cwd=directory,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        return {"success": True, "message": f"{action.title()}ed {dc['name']}"}
    else:
        return {"success": False, "error": result.stderr}
```

## Web Interface

The dashboard serves an embedded HTML page with a dark theme:

```python
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Local Services Dashboard</title>
    <style>
        :root {
            --bg: #1a1a2e;
            --card-bg: #16213e;
            --text: #eee;
            --text-muted: #888;
            --green: #00d26a;
            --red: #ff6b6b;
            --blue: #4dabf7;
            --border: #2a2a4a;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            padding: 2rem;
            min-height: 100vh;
        }
        h1 { margin-bottom: 2rem; font-weight: 300; font-size: 1.8rem; }
        h2 {
            font-size: 1rem;
            font-weight: 500;
            color: var(--text-muted);
            margin: 2rem 0 1rem;
            text-transform: uppercase;
            letter-spacing: 0.1em;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 1rem;
        }
        .card {
            background: var(--card-bg);
            border-radius: 8px;
            padding: 1.25rem;
            border: 1px solid var(--border);
        }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.75rem;
        }
        .card-title { font-size: 1.1rem; font-weight: 500; }
        .status {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            font-size: 0.85rem;
        }
        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
        }
        .status-dot.running {
            background: var(--green);
            box-shadow: 0 0 8px var(--green);
        }
        .status-dot.stopped { background: var(--red); }
        .card-meta {
            font-size: 0.8rem;
            color: var(--text-muted);
            margin-bottom: 1rem;
        }
        .card-meta a { color: var(--blue); text-decoration: none; }
        .card-meta a:hover { text-decoration: underline; }
        .card-actions { display: flex; gap: 0.5rem; }
        button {
            padding: 0.5rem 1rem;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85rem;
            transition: opacity 0.2s;
        }
        button:hover { opacity: 0.8; }
        button:disabled { opacity: 0.5; cursor: not-allowed; }
        .btn-start { background: var(--green); color: #000; }
        .btn-stop { background: var(--red); color: #fff; }
        .btn-open { background: var(--blue); color: #000; }
        .docker-containers {
            font-size: 0.75rem;
            color: var(--text-muted);
            margin-top: 0.5rem;
        }
        .refresh-btn {
            position: fixed;
            bottom: 2rem;
            right: 2rem;
            background: var(--blue);
            color: #000;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            font-size: 1.5rem;
        }
        .toast {
            position: fixed;
            bottom: 2rem;
            left: 50%;
            transform: translateX(-50%);
            background: var(--card-bg);
            border: 1px solid var(--border);
            padding: 1rem 2rem;
            border-radius: 8px;
            display: none;
        }
        .toast.show { display: block; }
        .toast.success { border-color: var(--green); }
        .toast.error { border-color: var(--red); }
    </style>
</head>
<body>
    <h1>Local Services Dashboard</h1>

    <h2>Development Servers</h2>
    <div class="grid" id="services"></div>

    <h2>Docker Compose</h2>
    <div class="grid" id="docker"></div>

    <h2>SSH Tunnels</h2>
    <div class="grid" id="tunnels"></div>

    <button class="refresh-btn" onclick="refresh()">↻</button>
    <div class="toast" id="toast"></div>

    <script>
        async function fetchStatus() {
            const res = await fetch('/api/status');
            return res.json();
        }

        function renderService(svc, type) {
            const running = svc.running;
            const statusClass = running ? 'running' : 'stopped';
            const statusText = running ? 'Running' : 'Stopped';

            let meta = '';
            if (svc.domain) {
                meta += `<a href="https://${svc.domain}" target="_blank">${svc.domain}</a>`;
            }
            if (svc.port) meta += ` · Port ${svc.port}`;
            if (svc.pid) meta += ` · PID ${svc.pid}`;

            let actions = '';
            if (type === 'service') {
                actions = `
                    <button class="btn-start" onclick="action('start', '${svc.name}')" ${running ? 'disabled' : ''}>Start</button>
                    <button class="btn-stop" onclick="action('stop', '${svc.name}')" ${!running ? 'disabled' : ''}>Stop</button>
                `;
            } else if (type === 'docker') {
                actions = `
                    <button class="btn-start" onclick="dockerAction('start', '${svc.name}')" ${running ? 'disabled' : ''}>Start</button>
                    <button class="btn-stop" onclick="dockerAction('stop', '${svc.name}')" ${!running ? 'disabled' : ''}>Stop</button>
                `;
            }

            if (svc.domain) {
                actions += `<button class="btn-open" onclick="window.open('https://${svc.domain}', '_blank')">Open</button>`;
            }

            let extra = '';
            if (svc.running_count !== undefined) {
                extra = `<div class="docker-containers">${svc.running_count}/${svc.total_count} containers running</div>`;
            }

            return `
                <div class="card">
                    <div class="card-header">
                        <span class="card-title">${svc.name}</span>
                        <span class="status">
                            <span class="status-dot ${statusClass}"></span>
                            ${statusText}
                        </span>
                    </div>
                    <div class="card-meta">${meta}</div>
                    <div class="card-actions">${actions}</div>
                    ${extra}
                </div>
            `;
        }

        async function refresh() {
            const data = await fetchStatus();
            document.getElementById('services').innerHTML =
                data.services.map(s => renderService(s, 'service')).join('');
            document.getElementById('docker').innerHTML =
                data.docker_compose.map(s => renderService(s, 'docker')).join('');
            document.getElementById('tunnels').innerHTML =
                data.tunnels.map(s => renderService(s, 'tunnel')).join('');
        }

        function showToast(message, type) {
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.className = 'toast show ' + type;
            setTimeout(() => toast.className = 'toast', 3000);
        }

        async function action(act, name) {
            const res = await fetch(`/api/${act}?name=${encodeURIComponent(name)}`, {method: 'POST'});
            const data = await res.json();
            showToast(data.message || data.error, data.success ? 'success' : 'error');
            setTimeout(refresh, 1000);
        }

        async function dockerAction(act, name) {
            const res = await fetch(`/api/docker/${act}?name=${encodeURIComponent(name)}`, {method: 'POST'});
            const data = await res.json();
            showToast(data.message || data.error, data.success ? 'success' : 'error');
            setTimeout(refresh, 2000);
        }

        refresh();
        setInterval(refresh, 10000);
    </script>
</body>
</html>
"""
```

## HTTP Handler Implementation

```python
class DashboardHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress logging

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_html(self, html):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(html.encode())

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/" or parsed.path == "":
            self.send_html(HTML_TEMPLATE)

        elif parsed.path == "/api/status":
            config = load_config()
            services = [get_service_status(s) for s in config.get("services", [])]
            docker = [get_docker_compose_status(d) for d in config.get("docker_compose", [])]
            tunnels = [get_service_status(t) for t in config.get("tunnels", [])]
            self.send_json({
                "services": services,
                "docker_compose": docker,
                "tunnels": tunnels
            })

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        name = params.get("name", [None])[0]

        if not name:
            self.send_json({"success": False, "error": "Missing name"}, 400)
            return

        config = load_config()

        if parsed.path == "/api/start":
            service = next((s for s in config.get("services", []) if s["name"] == name), None)
            if service:
                self.send_json(start_service(service))
            else:
                self.send_json({"success": False, "error": "Not found"}, 404)

        elif parsed.path == "/api/stop":
            service = next((s for s in config.get("services", []) if s["name"] == name), None)
            if service:
                self.send_json(stop_service(service))
            else:
                self.send_json({"success": False, "error": "Not found"}, 404)

        elif parsed.path == "/api/docker/start":
            dc = next((d for d in config.get("docker_compose", []) if d["name"] == name), None)
            if dc:
                self.send_json(docker_compose_action(dc, "start"))
            else:
                self.send_json({"success": False, "error": "Not found"}, 404)

        elif parsed.path == "/api/docker/stop":
            dc = next((d for d in config.get("docker_compose", []) if d["name"] == name), None)
            if dc:
                self.send_json(docker_compose_action(dc, "stop"))
            else:
                self.send_json({"success": False, "error": "Not found"}, 404)


def main():
    server = HTTPServer(("0.0.0.0", PORT), DashboardHandler)
    print(f"Dashboard running at http://localhost:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
```

## Running the Dashboard

```bash
# Direct execution
cd ~/projects/local-dashboard
python3 server.py

# Background execution (survives terminal close)
nohup python3 server.py > dashboard.log 2>&1 &
```

Access the dashboard at `http://localhost:9000`.

## Adding Services

Edit `services.json` to add new services. The dashboard reloads the configuration on each request, eliminating the need for restart.

### Standard Dev Server

```json
{
  "name": "My React App",
  "domain": "react.lan",
  "port": 3000,
  "directory": "/home/user/projects/react-app",
  "start_cmd": "npm start",
  "process_match": "react-scripts start"
}
```

### Static File Server

```json
{
  "name": "Documentation",
  "domain": "docs.lan",
  "port": 8080,
  "directory": "/home/user/projects/docs/build",
  "start_cmd": "python3 -m http.server 8080",
  "process_match": "http.server 8080"
}
```

### Docker Compose Project

```json
{
  "name": "API Stack",
  "domain": "api.lan",
  "directory": "/home/user/projects/api",
  "compose_file": "docker-compose.yml"
}
```

## Extensions

This dashboard functions locally. For network-wide access from other machines:

1. Configure a reverse proxy (Caddy/nginx)
2. Set up DNS resolution for custom domains
3. Configure firewall rules

The next post in this series covers network-wide access with Caddy and local DNS.
