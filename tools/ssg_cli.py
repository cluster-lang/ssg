#!/usr/bin/env python3
"""
Cluster-SSG CLI & Live Dev Server Runner
"""
import sys
import os
import time
import subprocess
import http.server
import socketserver
import threading

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NATIVE_BIN = os.path.join(PROJECT_DIR, "bin", "cluster-ssg-core")

def run_native(args=None):
    if not os.path.exists(NATIVE_BIN):
        # Fallback to direct bin
        alt = os.path.join(PROJECT_DIR, "bin", "cluster-ssg")
        if os.path.exists(alt) and not os.path.samefile(alt, __file__):
            subprocess.run([alt], cwd=PROJECT_DIR)
            return
    cmd = [NATIVE_BIN] + (args or [])
    subprocess.run(cmd, cwd=PROJECT_DIR)

def cmd_preview(target_file):
    if not os.path.exists(target_file):
        print(f"Error: file not found: {target_file}")
        sys.exit(1)
    
    # Run build first to ensure dist is ready
    run_native()
    
    # Find matching html in dist
    base = os.path.splitext(os.path.basename(target_file))[0]
    html_target = os.path.join(PROJECT_DIR, "dist", f"{base}.html")
    if os.path.exists(html_target):
        print(f"✓ Opening live rendered preview for: {target_file}")
        print(f"  Destination: {html_target}")
        subprocess.run(["xdg-open", html_target], stderr=subprocess.DEVNULL)
    else:
        print(f"Built preview, please open: {html_target}")

def cmd_serve(port=3000):
    dist_dir = os.path.join(PROJECT_DIR, "dist")
    site_dir = os.path.join(PROJECT_DIR, "site")

    # Initial build
    run_native()

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=dist_dir, **kwargs)
        def log_message(self, format, *args):
            pass

    def file_watcher():
        last_mtime = 0
        while True:
            max_mtime = 0
            for root, _, files in os.walk(site_dir):
                for f in files:
                    if f.endswith(('.cld', '.html', '.css', '.js')):
                        p = os.path.join(root, f)
                        try:
                            mt = os.path.getmtime(p)
                            if mt > max_mtime: max_mtime = mt
                        except OSError: pass
            if last_mtime != 0 and max_mtime > last_mtime:
                print("\n[Watcher] Changes detected in site/! Recompiling...")
                run_native()
                print("[Watcher] ✓ Rebuild complete.")
            last_mtime = max_mtime
            time.sleep(1.0)

    t = threading.Thread(target=file_watcher, daemon=True)
    t.start()

    print(f"\n=================================================================")
    print(f"  ⚡ Cluster-SSG Live Dev Server running on http://localhost:{port}")
    print(f"  Watching {site_dir} for instant changes...")
    print(f"  Press Ctrl+C to stop.")
    print(f"=================================================================\n")

    with socketserver.TCPServer(("", port), QuietHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("build", "--build"):
        if "--binary" in sys.argv:
            trigger = os.path.join(PROJECT_DIR, ".binary")
            open(trigger, "w").close()
            run_native()
            if os.path.exists(trigger): os.remove(trigger)
        else:
            run_native()
    elif sys.argv[1] == "preview":
        if len(sys.argv) < 3:
            print("Usage: cluster-ssg preview <file.cld>")
            sys.exit(1)
        cmd_preview(sys.argv[2])
    elif sys.argv[1] == "serve":
        port = 3000
        if len(sys.argv) >= 3 and sys.argv[2].isdigit():
            port = int(sys.argv[2])
        cmd_serve(port)
    elif sys.argv[1] in ("help", "--help", "-h"):
        print("Cluster-SSG (v1.0.0) — Blazing-Fast Static Site Generator")
        print("Usage:")
        print("  cluster-ssg build            Build lean static site into dist/")
        print("  cluster-ssg build --binary   Build with secure .clb binary bundles")
        print("  cluster-ssg serve [port]     Start live dev server with auto-rebuild")
        print("  cluster-ssg preview <file>   Compile & open rendered preview")
    else:
        run_native(sys.argv[1:])

if __name__ == "__main__":
    main()
