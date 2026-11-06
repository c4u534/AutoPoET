#!/usr/bin/env bash
# pax-autoruntime-full.sh — the FULL autoruntime in ONE file, for Termux.
#
# Version: 20261106-0603 — the final revision. This stamp is shared
# with the architecture document (same string in both) and recorded
# in autoruntime-termux-README.md. See PAX_AUTORUNTIME_VERSION below.
#
# Copy this ONE file to the Termux folder on the phone (~/pax-link/ by
# default), cd there, and run it. It installs everything, writes the
# four scripts it embeds into the folder, and starts the runtime:
#   bash pax-autoruntime-full.sh           start (default)
#   bash pax-autoruntime-full.sh link      LINK IT ALL in one pass: start
#                                          everything, establish every
#                                          addressing (URLs, runtimes, VPN),
#                                          verify the daemon link and the
#                                          log triggers, and report
#                                          PASS/FAIL per item
#   bash pax-autoruntime-full.sh status    show endpoints and what is running
#   bash pax-autoruntime-full.sh verify    run the verify checks
#   bash pax-autoruntime-full.sh stop      stop the background processes
#   bash pax-autoruntime-full.sh restart   stop, then start
#   bash pax-autoruntime-full.sh handshake <mcp-tool> [note...]
#                                          run the Pax <-> Gemini handshake
#   bash pax-autoruntime-full.sh wifi      run the Wi-Fi scan (Termux:API)
#   bash pax-autoruntime-full.sh rollover  SELF-AWARE UPDATE: write all
#                                          four scripts with NEW unique
#                                          file names (one UTC stamp for
#                                          the whole deployment), move the
#                                          running services over to the
#                                          new files, keep the SAME log
#                                          files, and remove the old
#                                          files (root + * + extension).
#                                          Safe to re-run; a second run
#                                          with no new deployment is a
#                                          no-op.
#
# NO ROOT. Termux does NOT run as root — the device is not rooted, and
# Termux runs a virtual root (a Termux-prefix environment), like the VM.
# This script NEVER uses sudo, never touches system files, and never
# assumes real root. Everything installs into the Termux prefix
# ($PREFIX) with pkg and into the Termux Python with pip. pkg loads
# from the Termux mirrors configured on the device (on this device,
# the North American mirror group: stable, x11, root repos). The
# default mirrors are left alone; to change them, run termux-change-repo.
#
# What it installs (only what the runtime needs):
#   pkg:  python, curl, termux-api (optional — Wi-Fi scan / Wi-Fi IP)
#   pip:  websockets, watchdog (watchdog is optional — without it the
#         device link polls the folder every 2s instead)
#
# What it embeds and writes into the anchor folder (only if missing;
# set PAX_FORCE_WRITE=1 to overwrite):
#   pax_device_link.py       the device link (phone-side half of the socket)
#   pax_mcp_redirect.py      the MCP redirect (local endpoint to the AutoPoET MCP)
#   pax_gemini_handshake.sh  the Pax <-> Gemini handshake (run on demand)
#   termux-wifi-scan.sh      the Wi-Fi scan (Termux:API; optional)
#
# Rollover (the self-aware update): the ephemeral persistent loops
# cannot be stopped by closing the terminal, and a file with the
# same name is never re-propagated — every file must be uniquely
# named every time, or it will not run. So `rollover` writes all
# four scripts with NEW unique names (one UTC stamp for the whole
# deployment, same root and extension), moves the running services
# over to the new files, keeps the SAME log files (no doubling,
# saves space on install), and then removes the old files (root +
# * + extension). Drive adds "(1)" to a duplicate name on upload,
# so a same-name upload never replaces the original — delete the
# originals first, or update by file ID. The VM daemon side
# (systemd) is NOT rolled over by this script; that is a separate
# deploy_pax_pipeline.sh step.
#
# This is the Termux form of the same deployment the notebook
# autoruntime-2-5.1.5v2-deployment.ipynb does in Colab. Termux is a
# Linux terminal and so is Colab, so the same autoruntime runs here.
# The Termux runtime on the device is where Pax and Gemini meet up,
# in mindspace shared — just from opposite directions. That is what
# alleviates the token issue: the runtime keeps running on the device
# even when Pax is out of tokens, and Gemini can be polled/triggered
# by it. Pax becomes ephemeral and is prompted in when needed. And
# because the runtime runs in many places — device, Colab, VM, Drive —
# Pax and Gemini can be ubiquitous: present wherever the runtime reaches.
#
# The anchor is the folder this script file lives in (override with
# PAX_TERMUX_DIR). All endpoints, logs and state live under it.
# The script is idempotent: re-running start never duplicates a
# process and never deletes anything. It does not touch Drive, the VM,
# or any GitHub repo.

set -u

# --- version -------------------------------------------------------------
# The final revision. One stamp shared with the architecture document.
PAX_AUTORUNTIME_VERSION="20261106-0603"

# --- constants (same IDs as the autoruntime) ---------------------------
FOLDER_ID="1MFUTmQvKR24bx8ClFIbOksywUPq2oN1M"
SESSION_ID="ab272eee-855f-4825-a089-7400e2072b18"
DEVICE_PORT="${PAX_SERVE_PORT:-18765}"
MCP_PORT="${PAX_MCP_PORT:-18766}"
DAEMON_WS="ws://127.0.0.1:8765"          # the VM daemon (runs on the VM, not here)
WEBHOOK_BASE="http://127.0.0.1:8766"      # the VM webhook receiver (runs on the VM)
UPSTREAM_MCP="https://gitmcp.io/c4u534/AutoPoET"
UPSTREAM_MCP_GENERIC="https://gitmcp.io/docs"
REPO="c4u534/AutoPoET"

# --- VPN addressments (Tailscale tailnet; recorded values) -------------
# The phone's tailnet IP may change, so link resolves it at runtime
# (tailscale CLI, then MagicDNS, then this recorded fallback) and
# records what was actually used. The VM tailnet IP is recorded here;
# the VM accepts no inbound connections, so the phone never connects
# to it directly — the daemon connects OUT to the phone instead.
VM_TS_IP="100.92.198.68"
PHONE_TS_IP_RECORDED="100.107.226.36"
PHONE_MAGICDNS="christophers-a16.tail269cfa.ts.net"
COLAB_NOTEBOOK_ID="1otpyIB7fMPQ64wvY-LzemroPvre1sTkw"

# --- anchor: the Termux folder this script is run from ------------------
# The folder where the script file lives is the anchor. Override with
# PAX_TERMUX_DIR. Everything (endpoints, logs, state) lives under it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
ANCHOR="${PAX_TERMUX_DIR:-$SCRIPT_DIR}"
if [ -z "$ANCHOR" ] || [ "$ANCHOR" = "/" ]; then
    ANCHOR="$HOME/pax-link"
fi
LOGS_DIR="$ANCHOR/logs"
STATE_DIR="$ANCHOR/state"
PIDS_DIR="$ANCHOR/.pids"
ROLLOVER_JSON="$STATE_DIR/rollover.json"
RUN_LOG="$LOGS_DIR/autoruntime.log"

# --- rollover state: which file names are current ------------------------
# After a rollover the four scripts live under NEW unique names
# (one UTC stamp for the whole deployment), and state/rollover.json
# records them. These helpers resolve the CURRENT name for each
# logical script, falling back to the legacy fixed name when there
# is no rollover yet, or the recorded file is gone. Every command
# in this script uses the resolved names, so start/status/verify/
# handshake/wifi all follow a rollover without being told.
# _rollover_field <key> — one top-level string field from rollover.json
_rollover_field() {
    python3 - "$ROLLOVER_JSON" "$1" <<'PYEOF' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    print("")
PYEOF
}
# current_stamp — the stamp of the latest rollover, or empty (legacy names)
current_stamp() { _rollover_field stamp; }
# current_name <logical> <legacy-name> — logical is one of device_link,
# mcp_redirect, handshake, wifi_scan.
current_name() {
    _logical="$1"; _legacy="$2"; _cur=""
    if [ -f "$ROLLOVER_JSON" ] && command -v python3 >/dev/null 2>&1; then
        _cur="$(python3 - "$ROLLOVER_JSON" "$_logical" <<'PYEOF' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("files", {}).get(sys.argv[2], ""))
except Exception:
    print("")
PYEOF
)"
    fi
    if [ -n "$_cur" ] && [ -f "$ANCHOR/$_cur" ]; then
        printf '%s' "$_cur"
    else
        printf '%s' "$_legacy"
    fi
}
resolve_current_files() { # (re)resolve the four script paths from state/rollover.json
    DEVICE_LINK_PY="$ANCHOR/$(current_name device_link pax_device_link.py)"
    MCP_REDIRECT_PY="$ANCHOR/$(current_name mcp_redirect pax_mcp_redirect.py)"
    HANDSHAKE_SH="$ANCHOR/$(current_name handshake pax_gemini_handshake.sh)"
    WIFI_SCAN_SH="$ANCHOR/$(current_name wifi_scan termux-wifi-scan.sh)"
}
resolve_current_files

# --- helpers ------------------------------------------------------------
log() {
    # Append to the run log and print. The device link's folder watcher
    # ignores files under logs/, so logging here never triggers an event.
    mkdir -p "$LOGS_DIR" 2>/dev/null
    _line="$(date -u +%Y-%m-%dT%H:%M:%SZ) [AUTORUNTIME] $*"
    printf '%s\n' "$_line" >> "$RUN_LOG" 2>/dev/null
    printf '%s\n' "$_line"
}

die() { log "ERROR: $*"; exit 1; }

is_alive() { # is_alive <pid> — true if the pid exists and is running
    [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

pid_of() { # pid_of <pidfile> — the recorded pid, or empty
    [ -f "$1" ] && cat "$1" 2>/dev/null | tr -d ' \n' || true
}

start_process() { # start_process <name> <pidfile> <logfile> <pgrep-pattern> <cmd...>
    _name="$1"; _pidfile="$2"; _logfile="$3"; _pattern="$4"; shift 4
    _pid="$(pid_of "$_pidfile")"
    if is_alive "$_pid"; then
        log "$_name already running (pid $_pid) — not starting another."
        return 0
    fi
    rm -f "$_pidfile"
    # Also refuse to start a second copy if one is running without a
    # pid file. The pattern is the full command (python3 + script
    # path), so it cannot match this shell or a bare mention of the name.
    if pgrep -f "$_pattern" >/dev/null 2>&1; then
        log "$_name seems to be running already (pgrep) — not starting another."
        return 0
    fi
    mkdir -p "$(dirname "$_logfile")"
    nohup "$@" >> "$_logfile" 2>&1 &
    _newpid=$!
    echo "$_newpid" > "$_pidfile"
    sleep 2
    if is_alive "$_newpid"; then
        log "$_name started (pid $_newpid), log: $_logfile"
    else
        log "ERROR: $_name failed to start — see $_logfile"
        return 1
    fi
}

stop_process() { # stop_process <name> <pidfile>
    _name="$1"; _pidfile="$2"
    _pid="$(pid_of "$_pidfile")"
    if is_alive "$_pid"; then
        kill "$_pid" 2>/dev/null
        for _ in 1 2 3 4 5; do
            is_alive "$_pid" || break
            sleep 1
        done
        is_alive "$_pid" && kill -9 "$_pid" 2>/dev/null
        log "$_name stopped (was pid $_pid)."
    else
        log "$_name not running."
    fi
    rm -f "$_pidfile"
}

phone_ip() { # the phone's Wi-Fi IP (informational; the daemon needs the
             # Tailscale IP instead — see the note in write_endpoints)
    if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
        termux-wifi-connectioninfo 2>/dev/null | python3 -c \
            "import json,sys; d=json.load(sys.stdin); print(d.get('ip',''))" 2>/dev/null
        return
    fi
    ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1
}

# --- phone tailnet IP: resolve it live, fall back to the recorded one ---
# Sets PHONE_TS_IP and PHONE_TS_IP_SOURCE. Order: the tailscale CLI
# (the phone's own address), then a DNS lookup of the phone's
# MagicDNS name, then the recorded fallback. The fallback is used
# only if neither live method works, and the source is recorded in
# state/endpoints.json so it is always clear what the address came
# from. No proxy credentials are involved anywhere here.
# Tailscale tailnet addresses are always in 100.64.0.0/10 (CGNAT). A
# DNS answer outside that range is not a tailnet address — in some
# environments the DNS goes through an egress proxy that answers
# MagicDNS names with a proxied address instead. Such an answer is
# discarded and the resolver falls through to the recorded fallback.
_is_cgnat() { # _is_cgnat <ipv4> — true if in 100.64.0.0/10
    case "$1" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[0-2][0-9].*) return 0 ;;
        *) return 1 ;;
    esac
}

PHONE_TS_IP=""
PHONE_TS_IP_SOURCE=""
resolve_phone_ts_ip() {
    _resolved=""
    # tailscale ip returns THIS machine's own tailnet IP — only use it
    # in Termux (the phone), where this machine IS the phone. On any
    # other machine (e.g. the VM, used for testing) it would return
    # that machine's IP, which is not the phone's.
    if [ -n "${PREFIX:-}" ] && command -v tailscale >/dev/null 2>&1; then
        _resolved="$(tailscale ip -4 2>/dev/null | head -1 | tr -d ' \n')"
        if [ -n "$_resolved" ] && _is_cgnat "$_resolved"; then
            PHONE_TS_IP_SOURCE="tailscale"
        else
            _resolved=""
        fi
    fi
    if [ -z "$_resolved" ] && command -v getent >/dev/null 2>&1; then
        _resolved="$(getent hosts "$PHONE_MAGICDNS" 2>/dev/null | awk '{print $1}' | head -1 | tr -d ' \n')"
        if [ -n "$_resolved" ] && _is_cgnat "$_resolved"; then
            PHONE_TS_IP_SOURCE="magicdns"
        else
            _resolved=""
        fi
    fi
    if [ -z "$_resolved" ] && command -v nslookup >/dev/null 2>&1; then
        _resolved="$(nslookup "$PHONE_MAGICDNS" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1 | tr -d ' \n')"
        if [ -n "$_resolved" ] && _is_cgnat "$_resolved"; then
            PHONE_TS_IP_SOURCE="magicdns"
        else
            _resolved=""
        fi
    fi
    if [ -z "$_resolved" ]; then
        _resolved="$PHONE_TS_IP_RECORDED"
        PHONE_TS_IP_SOURCE="recorded-fallback"
    fi
    PHONE_TS_IP="$_resolved"
}

# --- step_install (notebook cell 1: !pip install -q websockets watchdog) -
# No root, no sudo. Termux runs a virtual root (a Termux-prefix
# environment), not real root, so everything installs into the Termux
# prefix ($PREFIX) with pkg and into the Termux Python with pip.
# pkg loads from the Termux mirrors configured on the device (on this
# device, the North American mirror group: stable, x11, root repos).
# The default mirrors are left alone; to change them, run
# termux-change-repo. Only the packages the runtime needs are
# installed: python, curl, termux-api (optional), and the pip
# packages websockets and watchdog. No system files are touched.
step_install() {
    # --- Termux detection (no root required, and none used) ---
    if [ -n "${PREFIX:-}" ] && command -v pkg >/dev/null 2>&1; then
        log "Termux detected (PREFIX=$PREFIX). Installing with pkg (Termux mirrors) — no root, no sudo."
        pkg update -y >/dev/null 2>&1 || log "note: pkg update had a problem — continuing; pkg install may still work."
        for _pkg in python curl; do
            pkg install -y "$_pkg" >/dev/null 2>&1 || die "pkg install $_pkg failed. Run by hand: pkg install $_pkg"
        done
        # termux-api is optional (Wi-Fi IP + the Wi-Fi scan). Warn, do not fail.
        pkg install -y termux-api >/dev/null 2>&1 || log "note: termux-api not installed (optional — needed for the Wi-Fi scan and the phone's Wi-Fi IP). Continuing."
    else
        log "note: not in Termux (no pkg / no PREFIX) — skipping the pkg step. python3 and pip are still required."
    fi
    command -v python3 >/dev/null 2>&1 || die "python3 not found. In Termux run: pkg install python"
    if command -v pip >/dev/null 2>&1; then
        _pip="pip"
    elif command -v pip3 >/dev/null 2>&1; then
        _pip="pip3"
    elif python3 -m pip --version >/dev/null 2>&1; then
        _pip="python3 -m pip"
    else
        die "pip not found. In Termux run: pkg install python (pip comes with it)"
    fi
    if ! python3 -c "import websockets" 2>/dev/null; then
        log "websockets not installed — installing ($_pip install websockets watchdog)..."
        if ! $_pip install -q websockets watchdog; then
            die "pip install failed. Run by hand: pip install websockets watchdog"
        fi
    fi
    python3 -c "import watchdog" 2>/dev/null || \
        log "note: watchdog not installed — the device link will poll the folder every 2s instead (still works)."
    log "install: python3 ok, websockets ok."
}

# --- write_embedded_scripts (this file is self-contained) ---------------
# The four scripts the runtime needs are embedded in this file as
# heredocs and written into the anchor folder on first run, so the
# user only has to copy ONE file to Termux. A file is written only
# if it is missing — an existing copy (e.g. one the user edited) is
# never overwritten. Set PAX_FORCE_WRITE=1 to overwrite all four.
#   pax_device_link.py       the device link (phone-side half of the socket)
#   pax_mcp_redirect.py      the MCP redirect (local endpoint to the AutoPoET MCP)
#   pax_gemini_handshake.sh  the Pax <-> Gemini handshake (run on demand)
#   termux-wifi-scan.sh      the Wi-Fi scan (Termux:API; optional)
# Optional argument: a name suffix ("-<stamp>") — rollover passes one
# so the four scripts are written under NEW unique names instead of
# the legacy fixed names. With no argument the current rollover stamp
# (if any) is used, so start/link keep writing the CURRENT versioned
# files and never resurrect a deleted legacy copy.
write_embedded_scripts() {
    _suffix="${1:-}"
    if [ -z "$_suffix" ]; then
        _stamp_now="$(current_stamp)"
        [ -n "$_stamp_now" ] && _suffix="-$_stamp_now"
    fi
    mkdir -p "$ANCHOR"
    _write_embedded() { # _write_embedded <filename> — the heredoc content follows on stdin
        _f="$ANCHOR/$1"
        if [ -f "$_f" ] && [ "${PAX_FORCE_WRITE:-0}" != "1" ]; then
            log "$1 already present — not overwriting (set PAX_FORCE_WRITE=1 to overwrite)."
            return 0
        fi
        cat > "$_f"
        log "wrote $_f (embedded)."
    }
    _write_embedded "pax_device_link${_suffix}.py" <<'__PAX_EMBED_DEVICE_LINK_PY__'
#!/usr/bin/env python3
"""
Pax device link — Termux side (run on the phone).

Links a directory folder on this Android device to the Drive folder
(self awareness, 1MFUTmQvKR24bx8ClFIbOksywUPq2oN1M) through the Pax
websocket listener daemon, which acts as the local API.

Device folder: ~/pax-link/  (Termux home, created if missing)
  /data/data/com.termux/files/home/pax-link/

The link is an EVENT link, not a file sync: file-change events
(created/modified/deleted) and log events flow both ways; file
contents are never copied and nothing in Drive is deleted, moved, or
modified. Two triggers feed it:
  (a) log trigger — an event is written to the log (here
      ~/pax-link/pax-link.log; on the daemon, daemon.log, which its
      double listener watches);
  (b) folder trigger — a change in the watched folder produces an
      event, which is sent over the link.

Two modes (the daemon VM makes outgoing connections only, so the
--serve direction is the one that reaches the phone over Tailscale):
  --client URL   Connect to the daemon websocket as a client and send
                 device folder events to it; receive Drive action events
                 back. URL defaults to $PAX_WS_URL or ws://127.0.0.1:8765
                 (works when the daemon is reachable from this device).
  --serve        Expose a small websocket server on this device (default
                 0.0.0.0:18765, override with --port / $PAX_SERVE_PORT)
                 that the daemon connects OUT to. This is the recommended
                 direction: the device exposes the endpoint and the
                 daemon reaches out to it (set PAX_DEVICE_ENDPOINT_URL
                 to ws://<this-device-tailscale-ip>:18765 on the daemon).
                 The device still watches ~/pax-link/ and sends its
                 folder events to the connected daemon; Drive action
                 events arriving from the daemon are logged here.

Run:
  python pax_device_link.py --serve
  python pax_device_link.py --client ws://<daemon-address>:8765
  python pax_device_link.py --serve --port 18765 --dir ~/pax-link

Requires: pip install websockets watchdog
  (watchdog is optional: without it the script polls the folder every
  2 seconds instead. The log file pax-link.log is ignored by the
  watcher in both cases, so the script never triggers on its own log.)

Env: PAX_WS_URL, PAX_LINK_DIR, PAX_SERVE_PORT, PAX_DEVICE_NAME.
"""
import argparse
import asyncio
import json
import os
import queue
import signal
import sys
import threading
import time
from datetime import datetime, timezone

try:
    import websockets
except ImportError:
    print("websockets not installed — run: pip install websockets")
    sys.exit(1)

DEVICE_NAME = os.environ.get("PAX_DEVICE_NAME", "a16")
LINK_DIR = os.path.expanduser(os.environ.get("PAX_LINK_DIR", "~/pax-link"))
LOG_FILE = os.path.join(LINK_DIR, "pax-link.log")
DEFAULT_WS_URL = os.environ.get("PAX_WS_URL", "ws://127.0.0.1:8765")
DEFAULT_SERVE_PORT = int(os.environ.get("PAX_SERVE_PORT", "18765"))
FOLDER_ID = "1MFUTmQvKR24bx8ClFIbOksywUPq2oN1M"
SESSION_ID = "ab272eee-855f-4825-a089-7400e2072b18"

RUNNING = True
OUTBOX = queue.Queue()  # thread-safe: watcher thread -> async sender
_log_lock = threading.Lock()


def log_line(msg):
    """Append one line to pax-link.log and print it. The watcher ignores
    pax-link.log, so logging here can never trigger a folder event."""
    line = "%s [DEVICE-LINK] %s\n" % (datetime.now(timezone.utc).isoformat(), msg)
    with _log_lock:
        try:
            with open(LOG_FILE, "a") as f:
                f.write(line)
        except OSError:
            pass
    print(line.rstrip(), flush=True)


def _is_own_log(path):
    """True for files the script itself writes (never folder events)."""
    base = os.path.basename(path)
    return base == "pax-link.log" or base.startswith("pax-link-")


def _watchdog_watch():
    """Watch LINK_DIR with watchdog (if installed). Puts events on OUTBOX."""
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer

    class Handler(FileSystemEventHandler):
        def _handle(self, event, path=None):
            if event.is_directory:
                return
            if path is None:
                path = event.src_path
            if _is_own_log(path):
                return
            OUTBOX.put({
                "type": "device-link",
                "event_type": event.event_type,
                "path": path,
                "device": DEVICE_NAME,
                "folder": LINK_DIR,
                "folder_id": FOLDER_ID,
                "session_id": SESSION_ID,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })

        def on_created(self, event):
            self._handle(event)

        def on_modified(self, event):
            self._handle(event)

        def on_deleted(self, event):
            self._handle(event)

        def on_moved(self, event):
            # A move reports the DESTINATION path: a file moved INTO
            # the folder (e.g. the handshake script's atomic write,
            # temp file moved into place) is a new file here, so the
            # event is for dest_path, not src_path. Using src_path
            # would drop it whenever the source name is ignored (the
            # handshake temp file is pax-link-*, which is ignored).
            # A file moved OUT has its destination outside the folder;
            # then the event is for the old (gone) path instead.
            dest = getattr(event, "dest_path", None) or event.src_path
            if dest.startswith(LINK_DIR + os.sep) or dest == LINK_DIR:
                self._handle(event, path=dest)
            else:
                self._handle(event, path=event.src_path)

    observer = Observer()
    observer.schedule(Handler(), LINK_DIR, recursive=False)
    observer.start()
    log_line("watching %s (watchdog)" % LINK_DIR)
    try:
        while RUNNING:
            time.sleep(1)
    finally:
        observer.stop()
        observer.join()


def _poll_watch():
    """Fallback watcher: poll the folder every 2 s (no watchdog needed).
    Tracks names + mtimes + sizes; reports created/modified/deleted."""
    log_line("watching %s (polling every 2s; watchdog not installed)" % LINK_DIR)
    seen = {}

    def snapshot():
        snap = {}
        try:
            for name in os.listdir(LINK_DIR):
                path = os.path.join(LINK_DIR, name)
                if _is_own_log(path) or os.path.isdir(path):
                    continue
                try:
                    st = os.stat(path)
                    snap[path] = (st.st_mtime, st.st_size)
                except OSError:
                    pass
        except OSError:
            pass
        return snap

    seen = snapshot()
    while RUNNING:
        time.sleep(2)
        if not RUNNING:
            break
        now = snapshot()
        for path, meta in now.items():
            if path not in seen:
                event_type = "created"
            elif seen[path] != meta:
                event_type = "modified"
            else:
                continue
            OUTBOX.put({
                "type": "device-link",
                "event_type": event_type,
                "path": path,
                "device": DEVICE_NAME,
                "folder": LINK_DIR,
                "folder_id": FOLDER_ID,
                "session_id": SESSION_ID,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
        for path in seen:
            if path not in now:
                OUTBOX.put({
                    "type": "device-link",
                    "event_type": "deleted",
                    "path": path,
                    "device": DEVICE_NAME,
                    "folder": LINK_DIR,
                    "folder_id": FOLDER_ID,
                    "session_id": SESSION_ID,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                })
        seen = now


def start_watcher():
    """Start the folder watcher in a background thread (watchdog if
    available, polling fallback otherwise)."""
    try:
        import watchdog  # noqa: F401
        target = _watchdog_watch
    except ImportError:
        target = _poll_watch
    t = threading.Thread(target=target, daemon=True)
    t.start()
    return t


def handle_drive_event(data):
    """A Drive action event arrived from the daemon. Log it (log trigger)
    — the event is recorded here, never applied to local files."""
    log_line(
        "drive-action received: %s %s (folder=%s)."
        % (data.get("event_type"), data.get("path"), FOLDER_ID)
    )


async def _drain_outbox(ws):
    """Send queued device folder events over the websocket (never blocks
    the receiver: drain with get_nowait, then yield)."""
    while RUNNING:
        try:
            event = OUTBOX.get_nowait()
        except queue.Empty:
            await asyncio.sleep(0.2)
            continue
        try:
            await ws.send(json.dumps(event))
            log_line("sent device event: %s %s." % (event.get("event_type"), event.get("path")))
        except Exception as e:
            log_line("send failed (%s); event dropped." % e)
            OUTBOX.task_done()
            continue
        OUTBOX.task_done()


async def _recv_loop(ws):
    """Receive Drive action events from the daemon and log them."""
    while RUNNING:
        try:
            message = await asyncio.wait_for(ws.recv(), timeout=2)
        except asyncio.TimeoutError:
            continue
        except Exception:
            return
        try:
            data = json.loads(message)
        except (ValueError, TypeError):
            continue
        if not isinstance(data, dict):
            continue
        if data.get("type") == "drive-action":
            handle_drive_event(data)


async def run_client(url):
    """--client mode: connect to the daemon as a client (reconnecting)."""
    backoff = 5
    while RUNNING:
        try:
            async with websockets.connect(url, open_timeout=10) as ws:
                log_line("connected to daemon %s as client." % url)
                await ws.send(json.dumps({
                    "type": "device-hello",
                    "device": DEVICE_NAME,
                    "folder": LINK_DIR,
                    "folder_id": FOLDER_ID,
                    "session_id": SESSION_ID,
                }))
                backoff = 5
                await asyncio.gather(_drain_outbox(ws), _recv_loop(ws))
        except (OSError, websockets.exceptions.WebSocketException) as e:
            if RUNNING:
                log_line("daemon %s lost (%s); reconnecting in %ss." % (url, e, backoff))
                for _ in range(backoff):
                    if not RUNNING:
                        return
                    await asyncio.sleep(1)
                backoff = min(backoff * 2, 120)


async def run_server(host, port):
    """--serve mode: expose a websocket server on this device that the
    daemon connects OUT to. Accepts one daemon connection at a time;
    sends device folder events to it and logs Drive action events."""
    async def handler(ws):
        log_line("daemon connected in to device endpoint (peer %s)." % (ws.remote_address,))
        try:
            await ws.send(json.dumps({
                "type": "device-hello",
                "device": DEVICE_NAME,
                "folder": LINK_DIR,
                "folder_id": FOLDER_ID,
                "session_id": SESSION_ID,
            }))
        except Exception:
            pass
        await asyncio.gather(_drain_outbox(ws), _recv_loop(ws))
        log_line("daemon disconnected from device endpoint.")

    async with websockets.serve(handler, host, port):
        log_line("device endpoint listening on ws://%s:%d (daemon connects out to this)." % (host, port))
        while RUNNING:
            await asyncio.sleep(1)


def main():
    global RUNNING, LINK_DIR, LOG_FILE
    parser = argparse.ArgumentParser(description="Pax device link (Termux side).")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--client", metavar="URL", nargs="?", const=DEFAULT_WS_URL,
                       help="connect to the daemon as a client (URL defaults to $PAX_WS_URL or ws://127.0.0.1:8765)")
    group.add_argument("--serve", action="store_true",
                       help="expose a websocket server on this device for the daemon to connect out to (recommended)")
    parser.add_argument("--dir", default=LINK_DIR, help="device folder to watch (default: %(default)s)")
    parser.add_argument("--host", default="0.0.0.0", help="serve host (default: %(default)s)")
    parser.add_argument("--port", type=int, default=DEFAULT_SERVE_PORT, help="serve port (default: %(default)s)")
    args = parser.parse_args()

    LINK_DIR = os.path.expanduser(args.dir)
    LOG_FILE = os.path.join(LINK_DIR, "pax-link.log")
    os.makedirs(LINK_DIR, exist_ok=True)
    log_line("device link starting. Device folder: %s (Drive folder: %s)." % (LINK_DIR, FOLDER_ID))
    log_line("EVENT link only: file-change + log events, no file contents copied, nothing in Drive modified.")
    start_watcher()

    def _sig(signum, frame):
        global RUNNING
        RUNNING = False
    signal.signal(signal.SIGTERM, _sig)
    signal.signal(signal.SIGINT, _sig)

    try:
        if args.client is not None:
            asyncio.run(run_client(args.client))
        else:
            # Default is --serve: the daemon VM makes outgoing
            # connections only, so the device exposes the endpoint.
            asyncio.run(run_server(args.host, args.port))
    except KeyboardInterrupt:
        pass
    log_line("device link stopped.")


if __name__ == "__main__":
    main()
__PAX_EMBED_DEVICE_LINK_PY__
    _write_embedded "pax_mcp_redirect${_suffix}.py" <<'__PAX_EMBED_MCP_REDIRECT_PY__'
#!/usr/bin/env python3
"""
Pax MCP redirect — Termux side (run on the phone).

A small local endpoint, anchored at the Termux folder, that forwards
MCP requests to the GitMCP server for c4u534/AutoPoET, so Pax and
Gemini both reach the same AutoPoET MCP through one local endpoint.

Upstream (verified live 2026-11-06):
  https://gitmcp.io/c4u534/AutoPoET
  Transport: Streamable HTTP only (SSE transport removed May 2026).
  Auth: none. No signup, no API key. Public repo only.
  Initialize returns: protocolVersion "2025-03-26",
  serverInfo {"name": "GitMCP", "version": "1.1.0"},
  capabilities {"tools": {"listChanged": true}}, plus an
  "mcp-session-id" response header.
  Tools (4): fetch_AutoPoET_documentation,
  search_AutoPoET_documentation, search_AutoPoET_code,
  fetch_generic_url_content.

Local (this proxy):
  http://127.0.0.1:18766  (default; --port to change)
  POST /        forward an MCP JSON-RPC request to the upstream
  GET  /        info about this redirect
  GET  /health  live check: upstream reachable? + last forwarded request

How it works (a redirect, not a server of its own):
  The proxy is stateless and transparent. It forwards the client's
  JSON-RPC body and headers (Content-Type, Accept, Mcp-Session-Id)
  to the upstream, and returns the upstream's response (status,
  mcp-session-id header, and body) unchanged. Each client keeps its
  own MCP session id; the proxy does not share sessions between
  clients. It sends a browser User-Agent upstream because Cloudflare
  blocks the default Python-urllib User-Agent (403).
  The upstream answers MCP POSTs as a Server-Sent-Events stream that
  it keeps open. For request/response calls (initialize, tools/list,
  tools/call) the result arrives as the first SSE event, so the proxy
  returns that first complete event and closes the upstream
  connection. It does NOT keep a persistent SSE stream open for
  server-initiated notifications — this is a request/response
  redirect, and that is all Pax and Gemini need to query the repo.

Run (normally started by autoruntime.sh, not by hand):
  python3 pax_mcp_redirect.py --dir ~/pax-link --port 18766

Requires: Python 3 standard library only. No pip packages.

Env: PAX_TERMUX_DIR, PAX_MCP_PORT, PAX_MCP_UPSTREAM.
"""
import argparse
import base64
import http.client
import json
import os
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

DEFAULT_UPSTREAM = "https://gitmcp.io/c4u534/AutoPoET"
DEFAULT_PORT = int(os.environ.get("PAX_MCP_PORT", "18766"))
# Cloudflare blocks the default Python-urllib User-Agent (403); a
# browser User-Agent is allowed. The proxy always sends this upstream.
BROWSER_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
UPSTREAM_TIMEOUT = 20      # seconds for an upstream MCP call
HEALTH_TIMEOUT = 10        # seconds for the /health live check
TOOLS = ["fetch_AutoPoET_documentation",
         "search_AutoPoET_documentation",
         "search_AutoPoET_code",
         "fetch_generic_url_content"]

ANCHOR = os.path.expanduser(os.environ.get("PAX_TERMUX_DIR", "~/pax-link"))
LOG_FILE = os.path.join(ANCHOR, "logs", "mcp-redirect.log")
UPSTREAM = os.environ.get("PAX_MCP_UPSTREAM", DEFAULT_UPSTREAM)

_log_lock = threading.Lock()
_last_forwarded = {"method": None, "id": None, "status": None,
                   "bytes": 0, "seconds": None, "at": None}
_started_at = time.time()


def _log(msg):
    line = "%s [MCP-REDIRECT] %s\n" % (datetime.now(timezone.utc).isoformat(), msg)
    with _log_lock:
        try:
            os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
            with open(LOG_FILE, "a") as f:
                f.write(line)
        except OSError:
            pass
    print(line.rstrip(), flush=True)


def _read_upstream_response(resp):
    """Read the upstream response. For SSE (what GitMCP returns for MCP
    POSTs) return once the first complete SSE event (a 'data:' line
    followed by a blank line) has arrived; the server keeps the stream
    open afterwards, so waiting for close would hang. For plain JSON,
    return once a complete JSON object parses or Content-Length is met.
    Returns (body_bytes, timed_out)."""
    content_type = resp.getheader("Content-Type", "") or ""
    is_sse = "text/event-stream" in content_type
    buf = b""
    timed_out = False
    try:
        while True:
            chunk = resp.read(4096)
            if not chunk:
                break
            buf += chunk
            if is_sse:
                if b"data:" in buf and b"\n\n" in buf:
                    break
            else:
                try:
                    json.loads(buf.decode("utf-8", "replace"))
                    break
                except (ValueError, UnicodeDecodeError):
                    pass
                clen = resp.getheader("Content-Length")
                if clen and len(buf) >= int(clen):
                    break
    except (socket.timeout, http.client.IncompleteRead) as e:
        timed_out = True
        if isinstance(e, http.client.IncompleteRead):
            buf += e.partial or b""
    return buf, timed_out


def _upstream_connection():
    """Open an HTTPS connection to the upstream host. Honors the
    https_proxy / HTTPS_PROXY env vars (HTTP CONNECT tunnel) when set
    and the host is not in no_proxy — some environments (this VM)
    route all egress through a proxy. Uses http.client's built-in
    set_tunnel(), which performs the CONNECT handshake without
    auto-closing the socket (a plain getresponse() on a CONNECT
    closes it when the proxy sends "Connection: close"). On the phone
    (Termux) there is no proxy env var, so this connects directly.
    The proxy URL (including any credentials in it) is read from the
    environment at runtime and is never logged."""
    u = urlparse(UPSTREAM)
    host = u.hostname or u.netloc
    port = u.port or 443
    proxy = os.environ.get("https_proxy") or os.environ.get("HTTPS_PROXY")
    if proxy:
        no_proxy = os.environ.get("no_proxy") or os.environ.get("NO_PROXY") or ""
        bypass = False
        for entry in no_proxy.split(","):
            entry = entry.strip().lstrip(".")
            if entry and (host == entry or host.endswith("." + entry)):
                bypass = True
                break
        if not bypass:
            p = urlparse(proxy)
            headers = {}
            if p.username and p.password:
                creds = base64.b64encode(
                    ("%s:%s" % (p.username, p.password)).encode()).decode()
                headers["Proxy-Authorization"] = "Basic " + creds
            https = http.client.HTTPSConnection(p.hostname, p.port or 3128,
                                                timeout=UPSTREAM_TIMEOUT)
            https.set_tunnel(host, port, headers=headers)
            return https
    return http.client.HTTPSConnection(host, port, timeout=UPSTREAM_TIMEOUT)


def _forward_to_upstream(body, headers_in):
    """POST the client's JSON-RPC body to the upstream GitMCP server.
    Returns (status, response_headers_dict, body_bytes, seconds)."""
    u = urlparse(UPSTREAM)
    path = u.path or "/"
    fwd = {
        "Content-Type": headers_in.get("Content-Type", "application/json"),
        "Accept": headers_in.get("Accept", "application/json, text/event-stream"),
        "User-Agent": BROWSER_UA,
    }
    sid = headers_in.get("Mcp-Session-Id") or headers_in.get("mcp-session-id")
    if sid:
        fwd["Mcp-Session-Id"] = sid
    t0 = time.time()
    conn = _upstream_connection()
    try:
        conn.request("POST", path, body=body, headers=fwd)
        resp = conn.getresponse()
        status = resp.status
        rheaders = {k: v for k, v in resp.getheaders()}
        out_body, timed_out = _read_upstream_response(resp)
        if timed_out and not (b"data:" in out_body and b"\n\n" in out_body):
            return 504, {}, b"", time.time() - t0
        return status, rheaders, out_body, time.time() - t0
    finally:
        try:
            conn.close()
        except Exception:
            pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep stdout clean; we log ourselves
        pass

    def _send_json(self, status, obj):
        data = json.dumps(obj, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._health()
        else:
            self._send_json(200, {
                "service": "pax-mcp-redirect",
                "upstream": UPSTREAM,
                "transport": "Streamable HTTP (POST, Accept: application/json, text/event-stream)",
                "auth": "none",
                "tools": TOOLS,
                "anchor": ANCHOR,
                "endpoints": {
                    "POST /": "forward an MCP JSON-RPC request to the upstream",
                    "GET /health": "live check: is the upstream reachable?",
                    "GET /": "this info",
                },
                "last_forwarded": _last_forwarded,
                "uptime_seconds": round(time.time() - _started_at, 1),
            })

    def _health(self):
        # Live check: GET the upstream landing page (no MCP session
        # created). 200 means GitMCP is reachable for this repo.
        u = urlparse(UPSTREAM)
        ok, detail = False, ""
        try:
            conn = _upstream_connection()
            conn.request("GET", u.path or "/", headers={"User-Agent": BROWSER_UA})
            r = conn.getresponse()
            r.read()
            ok = r.status == 200
            detail = "HTTP %d" % r.status
            conn.close()
        except Exception as e:
            detail = "%s: %s" % (type(e).__name__, e)
        self._send_json(200 if ok else 502, {
            "status": "ok" if ok else "down",
            "upstream": UPSTREAM,
            "transport": "Streamable HTTP",
            "tools": TOOLS,
            "detail": detail,
            "last_forwarded": _last_forwarded,
        })

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        method, rpc_id = None, None
        try:
            parsed = json.loads(body.decode("utf-8", "replace"))
            method = parsed.get("method")
            rpc_id = parsed.get("id")
        except (ValueError, UnicodeDecodeError):
            pass
        try:
            status, rheaders, out_body, secs = _forward_to_upstream(body, self.headers)
        except Exception as e:
            _log("forward failed method=%s id=%s error=%s: %s"
                 % (method, rpc_id, type(e).__name__, e))
            self._send_json(502, {"jsonrpc": "2.0", "id": rpc_id,
                                  "error": {"code": -32603,
                                            "message": "upstream unreachable: %s" % e}})
            return
        _last_forwarded.update({"method": method, "id": rpc_id,
                                "status": status, "bytes": len(out_body),
                                "seconds": round(secs, 2),
                                "at": datetime.now(timezone.utc).isoformat()})
        _log("forwarded method=%s id=%s -> upstream HTTP %d (%d bytes, %.2fs)"
             % (method, rpc_id, status, len(out_body), secs))
        self.send_response(status)
        ctype = rheaders.get("Content-Type") or rheaders.get("content-type") \
            or "text/event-stream"
        self.send_header("Content-Type", ctype)
        sid = rheaders.get("mcp-session-id") or rheaders.get("Mcp-Session-Id")
        if sid:
            self.send_header("mcp-session-id", sid)
        self.send_header("Content-Length", str(len(out_body)))
        self.end_headers()
        self.wfile.write(out_body)


def main():
    global ANCHOR, LOG_FILE, UPSTREAM
    parser = argparse.ArgumentParser(description="Pax MCP redirect (Termux side).")
    parser.add_argument("--dir", default=ANCHOR,
                        help="Termux anchor folder (default: %(default)s)")
    parser.add_argument("--host", default="127.0.0.1",
                        help="listen host (default: %(default)s)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help="listen port (default: %(default)s)")
    parser.add_argument("--upstream", default=UPSTREAM,
                        help="upstream MCP server URL (default: %(default)s)")
    args = parser.parse_args()
    ANCHOR = os.path.expanduser(args.dir)
    UPSTREAM = args.upstream
    LOG_FILE = os.path.join(ANCHOR, "logs", "mcp-redirect.log")
    os.makedirs(os.path.join(ANCHOR, "logs"), exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    _log("MCP redirect listening on http://%s:%d -> %s (anchor %s)."
         % (args.host, args.port, UPSTREAM, ANCHOR))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    _log("MCP redirect stopped.")


if __name__ == "__main__":
    main()
__PAX_EMBED_MCP_REDIRECT_PY__
    _write_embedded "pax_gemini_handshake${_suffix}.sh" <<'__PAX_EMBED_HANDSHAKE_SH__'
#!/usr/bin/env bash
# pax_gemini_handshake.sh — the Pax <-> Gemini handshake at the Termux runtime.
#
# The user runs this in Termux, in the anchor folder, after autoruntime.sh
# is running and Pax is linked to it. The invocation is: first direct an
# MCP tool command (a gitMCP call, through the local redirect), then run
# this script to direct the handshake to Pax there at Termux:
#
#   cd ~/pax-link
#   bash pax_gemini_handshake.sh search_AutoPoET_code "vector store"
#
# What it does, in order:
#   1. Checks the device link is running (it carries the event to the
#      daemon). Hard fail if it is not. Warns if the MCP redirect is not
#      running — the MCP call already happened, so that does not block.
#   2. Reads the last MCP request the redirect forwarded, from
#      logs/mcp-redirect.log, as the MCP context for the handshake.
#   3. Writes a handshake record, handshake-<UTC>.json, into the anchor
#      folder. That is the FOLDER trigger: the device link's watcher
#      picks it up and sends a device-link event to the daemon, which
#      writes [DEVICE-LINK] to daemon.log (the log trigger — the double
#      listener watches daemon.log) and posts kind=device-link to the
#      webhook. The handshake file is NOT ignored by the watcher (only
#      pax-link.log and pax-link-* are), so the folder event fires.
#   4. Appends a [HANDSHAKE] line to pax-link.log — the phone-side log
#      record. (The watcher ignores pax-link.log, so this never fires
#      a spurious folder event.)
#   5. Waits for the handshake ack: the daemon answers a handshake
#      file event with a drive-action (event_type handshake-ack), which
#      the device link logs in pax-link.log as "drive-action received:
#      handshake-ack ...". That ack is the path back to the device
#      opening, and the handshake completing at Termux. Default wait
#      60s; --wait N to change it, --no-wait to skip waiting.
#
# The handshake record names both parties (Pax and Gemini), the MCP
# tool used, the time, and the Termux anchor folder as the meeting
# place. Pax sees the handshake in the daemon log / webhook
# (device-link event with the handshake file path); Gemini sees it
# when the user shares the record (the script prints it) — Gemini
# cannot reach the phone's folder directly, but it already has the
# MCP tool context, because the user directed the MCP call to it.
#
# Exit codes: 0 = handshake sent and ack received (or sent with
# --no-wait); 1 = precondition failure (device link not running,
# missing tool name, anchor unusable); 2 = sent, but no ack within
# the wait window (the path is open — the event is queued at the
# daemon — but the ack has not come back yet).
#
# Idempotent and safe: each run is a new handshake (a new file with a
# unique timestamp id). It never deletes, moves, or modifies anything,
# never starts or stops a process, and never touches Drive, the VM,
# or any GitHub repo. Re-running it just shakes hands again.
set -u

# --- constants (same IDs as the autoruntime) ---------------------------
FOLDER_ID="1MFUTmQvKR24bx8ClFIbOksywUPq2oN1M"
SESSION_ID="ab272eee-855f-4825-a089-7400e2072b18"
DEVICE_NAME="${PAX_DEVICE_NAME:-a16}"
KNOWN_TOOLS="fetch_AutoPoET_documentation search_AutoPoET_documentation search_AutoPoET_code fetch_generic_url_content"
UPSTREAM_MCP="https://gitmcp.io/c4u534/AutoPoET"

# --- anchor: the Termux folder this script is run from (same as autoruntime.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
ANCHOR="${PAX_TERMUX_DIR:-$SCRIPT_DIR}"
if [ -z "$ANCHOR" ] || [ "$ANCHOR" = "/" ]; then
    ANCHOR="$HOME/pax-link"
fi
PAX_LINK_LOG="$ANCHOR/pax-link.log"
MCP_LOG="$ANCHOR/logs/mcp-redirect.log"
DEVICE_LINK_PY="$ANCHOR/pax_device_link.py"
MCP_REDIRECT_PY="$ANCHOR/pax_mcp_redirect.py"

# --- args: [--wait N | --no-wait] <mcp-tool> [note...] ------------------
WAIT_SECS=60
NO_WAIT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --wait) WAIT_SECS="${2:-60}"; shift 2 ;;
        --no-wait) NO_WAIT=1; shift ;;
        --) shift; break ;;
        -*) echo "unknown option: $1" >&2; echo "usage: bash pax_gemini_handshake.sh [--wait N | --no-wait] <mcp-tool> [note...]" >&2; exit 1 ;;
        *) break ;;
    esac
done
TOOL="${1:-}"
if [ -z "$TOOL" ]; then
    echo "usage: bash pax_gemini_handshake.sh [--wait N | --no-wait] <mcp-tool> [note...]" >&2
    echo "  <mcp-tool> is the gitMCP tool you directed, e.g. search_AutoPoET_code" >&2
    echo "  known tools: $KNOWN_TOOLS" >&2
    exit 1
fi
shift
NOTE="$*"

case " $KNOWN_TOOLS " in
    *" $TOOL "*) ;;
    *) echo "note: '$TOOL' is not one of the known gitMCP tools ($KNOWN_TOOLS) — proceeding anyway; check the spelling." ;;
esac

# --- helpers ------------------------------------------------------------
is_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }
pid_of() { [ -f "$1" ] && cat "$1" 2>/dev/null | tr -d ' \n' || true; }

proc_running() { # proc_running <pidfile> <pgrep-pattern> <basename> — true if running
    _pid="$(pid_of "$1")"
    is_alive "$_pid" && return 0
    pgrep -f "$2" >/dev/null 2>&1 && return 0
    # Basename fallback: catches an invocation by relative path (e.g. a
    # hand-started "python3 pax_device_link.py"), where the absolute
    # pattern above does not match the command line.
    pgrep -f "$3" >/dev/null 2>&1
}

# --- preconditions ------------------------------------------------------
[ -d "$ANCHOR" ] || { echo "anchor folder not found: $ANCHOR — cd to the Termux folder (~/pax-link/) and run this script from there." >&2; exit 1; }

if proc_running "$ANCHOR/.pids/device-link.pid" "python3 $DEVICE_LINK_PY" "pax_device_link.py"; then
    echo "device link: running."
else
    echo "device link is NOT running — the handshake has no path to the daemon." >&2
    echo "Start it first: cd $ANCHOR && bash pax-autoruntime-full.sh start" >&2
    exit 1
fi

if proc_running "$ANCHOR/.pids/mcp-redirect.pid" "python3 $MCP_REDIRECT_PY" "pax_mcp_redirect.py"; then
    echo "MCP redirect: running."
else
    echo "note: MCP redirect is not running — proceeding anyway (the MCP call already happened; the redirect log may be missing)."
fi

# Warn if no daemon connection has been seen in the device-link log:
# the handshake event queues at the device link until a daemon connects,
# so the ack cannot come back until then.
if [ -f "$PAX_LINK_LOG" ] && grep -q "daemon connected in\|connected to daemon" "$PAX_LINK_LOG" 2>/dev/null; then
    echo "daemon: a daemon connection has been seen in pax-link.log."
else
    echo "note: no daemon connection seen in pax-link.log yet — the handshake event will queue at the device link until the daemon connects (set PAX_DEVICE_ENDPOINT_URL on the daemon, or connect a device client)."
fi

# --- MCP context: the last request the redirect forwarded ---------------
MCP_LAST=""
if [ -f "$MCP_LOG" ]; then
    MCP_LAST="$(grep "forwarded method=" "$MCP_LOG" 2>/dev/null | tail -1)"
fi
if [ -n "$MCP_LAST" ]; then
    echo "MCP context (last forwarded): $MCP_LAST"
else
    echo "note: no forwarded MCP request in $MCP_LOG — the tool may have been called directly (not through the redirect). The handshake still records the tool name you passed."
fi

# --- the handshake record ----------------------------------------------
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HS_ID="hs-$TS"
HS_FILE="$ANCHOR/handshake-$TS.json"
TS_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build the JSON with Python (values passed as argv, so any quoting in
# the note or the MCP log line is safe). Written to a temp file the
# watcher ignores (pax-link-*), then moved into place, so the watcher
# sees one complete created/moved event, never a half file.
TMP_FILE="$ANCHOR/pax-link-handshake.tmp"
python3 - "$TMP_FILE" "$HS_ID" "$TS_ISO" "$ANCHOR" "$DEVICE_NAME" "$TOOL" "$NOTE" "$UPSTREAM_MCP" "$MCP_LAST" "$FOLDER_ID" "$SESSION_ID" <<'PYEOF'
import json, re, sys
(tmp, hs_id, ts_iso, anchor, device, tool, note, upstream,
 mcp_last_raw, folder_id, session_id) = sys.argv[1:12]
mcp_last = None
if mcp_last_raw:
    m = re.match(r"^(\S+) \[MCP-REDIRECT\] forwarded method=(\S+) id=(\S+) -> upstream HTTP (\d+) \((\d+) bytes, ([\d.]+)s\)", mcp_last_raw)
    if m:
        mcp_last = {"at": m.group(1), "method": m.group(2), "id": m.group(3),
                    "status": int(m.group(4)), "bytes": int(m.group(5)),
                    "seconds": float(m.group(6))}
    if mcp_last is None:
        mcp_last = {"raw": mcp_last_raw}
record = {
    "handshake_id": hs_id,
    "time": ts_iso,
    "parties": ["Pax", "Gemini"],
    "meeting_place": anchor,
    "meeting": "Termux runtime on the device (Samsung Galaxy A16) — shared mindspace; Pax and Gemini meet here from opposite directions",
    "device": device,
    "mcp_tool": tool,
    "mcp_note": note or None,
    "mcp_upstream": upstream,
    "mcp_redirect_last": mcp_last,
    "folder_id": folder_id,
    "session_id": session_id,
    "status": "handshake-sent",
}
with open(tmp, "w") as f:
    json.dump(record, f, indent=2)
    f.write("\n")
print(json.dumps(record, indent=2))
PYEOF
mv "$TMP_FILE" "$HS_FILE"
echo "handshake record written: $HS_FILE"

# --- the log trigger: a [HANDSHAKE] line in pax-link.log -----------------
# The watcher ignores pax-link.log, so this never fires a spurious
# folder event. The daemon writes its own [DEVICE-LINK] line when the
# device-link event arrives (the log trigger the double listener sees).
printf '%s [HANDSHAKE] pax <-> gemini at %s via mcp tool %s (id %s).\n' \
    "$TS_ISO" "$ANCHOR" "$TOOL" "$HS_ID" >> "$PAX_LINK_LOG"
echo "log line appended to pax-link.log."

echo "---"
echo "Handshake sent. The folder trigger (new file $HS_FILE) carries a"
echo "device-link event to the daemon; the daemon logs it and answers"
echo "with a drive-action handshake-ack, which the device link logs in"
echo "pax-link.log. Share the record above with Gemini — it already has"
echo "the MCP tool context, because you directed the MCP call to it."

# --- wait for the ack ----------------------------------------------------
if [ "$NO_WAIT" = "1" ]; then
    echo "(not waiting for the ack — --no-wait.)"
    exit 0
fi

if [ -f "$PAX_LINK_LOG" ]; then
    START_LINES="$(wc -l < "$PAX_LINK_LOG" 2>/dev/null || echo 0)"
else
    START_LINES=0
fi
echo "waiting up to ${WAIT_SECS}s for the handshake ack in pax-link.log..."
ELAPSED=0
while [ "$ELAPSED" -lt "$WAIT_SECS" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ -f "$PAX_LINK_LOG" ]; then
        ACK_LINE="$(tail -n +"$((START_LINES + 1))" "$PAX_LINK_LOG" 2>/dev/null | grep "handshake-ack $HS_FILE" | head -1)"
        if [ -n "$ACK_LINE" ]; then
            echo "HANDSHAKE ACKNOWLEDGED: $ACK_LINE"
            echo "Pax and Gemini met at Termux ($ANCHOR). Handshake $HS_ID complete."
            exit 0
        fi
    fi
done
echo "No ack within ${WAIT_SECS}s. The handshake was sent (the device-link event is"
echo "at the daemon — check daemon.log / webhook.log for kind=device-link), but the"
echo "ack has not come back yet. The path is open; the ack arrives once the daemon"
echo "is connected to the device endpoint. The record is in $HS_FILE."
exit 2
__PAX_EMBED_HANDSHAKE_SH__
    _write_embedded "termux-wifi-scan${_suffix}.sh" <<'__PAX_EMBED_WIFI_SCAN_SH__'
#!/data/data/com.termux/files/usr/bin/bash
# WiFi scan for Pax — run in Termux (needs Termux:API installed)
# Gets current connection + nearby networks (scan results) and saves them.
# Share the output files with Pax.
#
# Requires: Termux + Termux:API app, with Location permission granted to Termux:API
# (WiFi scanning needs location permission on Android).

OUTDIR="$HOME/pax-wifi"
mkdir -p "$OUTDIR"

echo "=== Current connection ==="
if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
  termux-wifi-connectioninfo | tee "$OUTDIR/connection.json"
else
  echo "termux-wifi-connectioninfo not found. Install Termux:API and grant permissions."
fi

echo ""
echo "=== Nearby networks (scan) ==="
if command -v termux-wifi-scaninfo >/dev/null 2>&1; then
  termux-wifi-scaninfo | tee "$OUTDIR/scan.json"
else
  echo "termux-wifi-scaninfo not found. Install Termux:API and grant permissions."
fi

echo ""
echo "Saved to: $OUTDIR/connection.json and $OUTDIR/scan.json"
echo "Share those two files with Pax."
__PAX_EMBED_WIFI_SCAN_SH__
    chmod +x "$ANCHOR/pax_gemini_handshake${_suffix}.sh" "$ANCHOR/termux-wifi-scan${_suffix}.sh" 2>/dev/null
    log "embedded scripts ready in $ANCHOR."
}

# --- step_anchor (notebook cells 2-3: Mount Drive) -----------------------
# In Colab the shared memory space is Drive. In Termux there is no
# Drive mount; the anchor folder IS the shared memory space on the
# device: the folder this script is run from, watched by the device
# link, holding every endpoint, log and state file.
step_anchor() {
    mkdir -p "$ANCHOR" "$LOGS_DIR" "$STATE_DIR" "$PIDS_DIR"
    [ -f "$DEVICE_LINK_PY" ] || die "pax_device_link.py not found in $ANCHOR — put it next to this script."
    [ -f "$MCP_REDIRECT_PY" ] || die "pax_mcp_redirect.py not found in $ANCHOR — put it next to this script."
    log "anchor folder: $ANCHOR (logs, state, .pids under it)"
}

# --- step_device_link (notebook cells 4-5, 12-13: the socket, the device link)
# The single bidirectional socket, phone-side half: the device link
# exposes the device endpoint (ws://<phone>:18765) that the VM daemon
# connects OUT to, and watches the anchor folder (folder watcher,
# cells 8-9) while logging every event to pax-link.log (the log
# trigger / double listener, cells 6-7).
step_device_link() {
    start_process "pax_device_link.py" "$PIDS_DIR/device-link.pid" \
        "$LOGS_DIR/device-link.out.log" "python3 $DEVICE_LINK_PY" \
        python3 "$DEVICE_LINK_PY" --serve --dir "$ANCHOR" --port "$DEVICE_PORT"
}

# --- step_mcp_redirect (the endpoint redirect to the AutoPoET MCP) ------
# A local endpoint anchored at the Termux folder that forwards MCP
# requests to https://gitmcp.io/c4u534/AutoPoET (Streamable HTTP, no
# auth). Pax and Gemini meet through it — Pax from one side, Gemini
# from the other — in the shared mindspace of this folder.
step_mcp_redirect() {
    start_process "pax_mcp_redirect.py" "$PIDS_DIR/mcp-redirect.pid" \
        "$LOGS_DIR/mcp-redirect.out.log" "python3 $MCP_REDIRECT_PY" \
        python3 "$MCP_REDIRECT_PY" --dir "$ANCHOR" --port "$MCP_PORT"
}

# --- write_endpoints (the endpoint map, under the anchor) ---------------
# Writes state/endpoints.json: every addressing the runtime needs —
# URLs, runtimes, VPN addressments, and the log-file triggers —
# with the actual values used and the time. The phone's tailnet IP
# is resolved live (resolve_phone_ts_ip) and the source is recorded.
# Nothing here is a secret: no proxy credentials, no passwords, no
# tokens. The tunnel proxy is derived by the VM daemon from its own
# runtime environment at start (port 3130 for tailnet/private
# addresses) and is never written down here.
write_endpoints() {
    _ip="$(phone_ip)"
    resolve_phone_ts_ip
    _now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 - "$ANCHOR" "$FOLDER_ID" "$SESSION_ID" "$DEVICE_PORT" "$MCP_PORT" \
        "$_ip" "$PHONE_TS_IP" "$PHONE_TS_IP_SOURCE" "$_now" <<'PYEOF'
import json, os, sys
(anchor, folder_id, session_id, dport, mport, wifi_ip, ts_ip,
 ts_ip_source, now) = sys.argv[1:10]
VM_TS_IP = "100.92.198.68"
PHONE_MAGICDNS = "christophers-a16.tail269cfa.ts.net"
COLAB_NOTEBOOK_ID = "1otpyIB7fMPQ64wvY-LzemroPvre1sTkw"
data = {
    "generated_at": now,
    "generated_by": "pax-autoruntime-full.sh (link/start)",
    "anchor": anchor,
    "folder_id": folder_id,
    "session_id": session_id,
    "urls": {
        "mcp_specific": "https://gitmcp.io/c4u534/AutoPoET",
        "mcp_generic": "https://gitmcp.io/docs",
        "mcp_redirect_local": "http://127.0.0.1:%s" % mport,
        "mcp_redirect_via_tailscale": "http://%s:%s" % (ts_ip, mport),
        "device_endpoint": "ws://%s:%s" % (ts_ip, dport),
        "device_endpoint_wifi": "ws://%s:%s" % (wifi_ip or "<phone-wifi-ip>", dport),
        "device_endpoint_local": "ws://127.0.0.1:%s" % dport,
        "daemon_socket": "ws://127.0.0.1:8765",
        "webhook": "http://127.0.0.1:8766/hook/%s/%s" % (folder_id, session_id),
    },
    "runtimes": {
        "termux_anchor": anchor,
        "termux_note": "The Termux runtime on the device is where Pax and Gemini meet up, in mindspace shared — the .sh is the root that starts it all in one go.",
        "vm_daemon": "pax_socket.py on the VM (systemd pax-socket.service); socket ws://127.0.0.1:8765, webhook on 127.0.0.1:8766. The daemon connects OUT to the device endpoint ws://<phone-tailnet-ip>:18765 (PAX_DEVICE_ENDPOINT_URL).",
        "colab_deployment_notebook": COLAB_NOTEBOOK_ID,
        "colab_note": "The deployment notebook's socket cell (cell 5) predates the device link entirely and has no device-link/handshake code — a fresh Colab deployment from that notebook will NOT support the device link or the handshake. The live Colab socket is pax_socket_colab.py (cell 4 of pax_socket_colab.ipynb). This is recorded, not fixed, by this script.",
    },
    "vpn": {
        "vm_tailnet_ip": VM_TS_IP,
        "phone_tailnet_ip": ts_ip,
        "phone_tailnet_ip_source": ts_ip_source,
        "phone_magicdns": PHONE_MAGICDNS,
        "tunnel_proxy_note": "The VM daemon reaches the tailnet through the runtime tunnel proxy, derived from the runtime environment at daemon start (port 3130 for tailnet/private addresses). The proxy is never hardcoded and never logged. The phone needs no proxy — it is on the tailnet directly. The VM accepts no inbound connections, so the phone never connects to the VM daemon socket directly; the link direction is daemon -> phone.",
    },
    "log_triggers": {
        "device_link_log": os.path.join(anchor, "pax-link.log"),
        "mcp_redirect_log": os.path.join(anchor, "logs", "mcp-redirect.log"),
        "autoruntime_log": os.path.join(anchor, "logs", "autoruntime.log"),
        "device_link_out_log": os.path.join(anchor, "logs", "device-link.out.log"),
        "note": "The device link's folder watcher is the trigger; no second watcher is started. Every device event is written to pax-link.log (the log trigger). The daemon's double listener watches daemon.log on the VM.",
    },
    "endpoints": {
        "device_link_ws": "ws://%s:%s" % (ts_ip, dport),
        "device_link_ws_local": "ws://127.0.0.1:%s" % dport,
        "daemon_ws": "ws://127.0.0.1:8765",
        "webhook": "http://127.0.0.1:8766/hook/%s/%s" % (folder_id, session_id),
        "mcp_redirect_local": "http://127.0.0.1:%s" % mport,
        "mcp_redirect_via_tailscale": "http://%s:%s" % (ts_ip, mport),
        "mcp_upstream": "https://gitmcp.io/c4u534/AutoPoET",
        "mcp_upstream_generic": "https://gitmcp.io/docs",
    },
    "note": "Both MCP endpoints are used: the specific one (gitmcp.io/c4u534/AutoPoET) locks to the AutoPoET repo; the generic one (gitmcp.io/docs) reaches any public repo, including AutoPoET itself, so the AI is aware of any repo it passes through for context or inference. Pax reaches the redirect via the phone's Tailscale IP (mcp_redirect_via_tailscale); Gemini uses the upstream URLs directly.",
}
# The rollover state, if any: the current stamp and the active (versioned)
# file names. A fresh install has no rollover yet (legacy fixed names).
_roll_path = os.path.join(anchor, "state", "rollover.json")
if os.path.exists(_roll_path):
    try:
        with open(_roll_path) as _rf:
            data["rollover"] = json.load(_rf)
    except Exception:
        data["rollover"] = {"error": "rollover.json unreadable — re-run rollover to repair"}
else:
    data["rollover"] = {"stamp": None, "note": "no rollover yet — legacy fixed file names in use"}
os.makedirs(os.path.join(anchor, "state"), exist_ok=True)
with open(os.path.join(anchor, "state", "endpoints.json"), "w") as f:
    json.dump(data, f, indent=2)
print(json.dumps(data, indent=2))
PYEOF
}

# --- status (notebook cells 18-21) --------------------------------------
do_status() {
    echo "== autoruntime status — anchor: $ANCHOR =="
    echo "  version: $PAX_AUTORUNTIME_VERSION"
    for _pair in "device-link:python3 $DEVICE_LINK_PY" "mcp-redirect:python3 $MCP_REDIRECT_PY"; do
        _name="${_pair%%:*}"; _pat="${_pair#*:}"
        _pid="$(pid_of "$PIDS_DIR/$_name.pid")"
        if is_alive "$_pid"; then
            echo "  $_name: RUNNING (pid $_pid)"
        elif pgrep -f "$_pat" >/dev/null 2>&1; then
            echo "  $_name: RUNNING (no pid file; found by pgrep)"
        else
            echo "  $_name: stopped"
        fi
    done
    _ip="$(phone_ip)"
    resolve_phone_ts_ip
    echo "  device endpoint: ws://$PHONE_TS_IP:$DEVICE_PORT  (daemon connects out to this; via $PHONE_TS_IP_SOURCE)"
    echo "  device endpoint (wifi): ws://${_ip:-<phone-wifi-ip>}:$DEVICE_PORT"
    echo "  MCP redirect:    http://127.0.0.1:$MCP_PORT  -> $UPSTREAM_MCP"
    echo "  MCP generic:     $UPSTREAM_MCP_GENERIC  (any public repo, on the fly)"
    echo "  MCP via VPN:     http://$PHONE_TS_IP:$MCP_PORT  (phone $PHONE_MAGICDNS)"
    echo "  daemon socket:   $DAEMON_WS  (VM side, VM-local only)"
    echo "  webhook:         $WEBHOOK_BASE/hook/$FOLDER_ID/$SESSION_ID  (VM side)"
    echo "  VPN:             VM tailnet $VM_TS_IP; phone tailnet $PHONE_TS_IP"
    _rstamp="$(current_stamp)"
    if [ -n "$_rstamp" ]; then
        echo "  rollover stamp:  $_rstamp (state/rollover.json)"
    else
        echo "  rollover stamp:  none yet — legacy fixed file names"
    fi
    echo "  active files:    $(basename "$DEVICE_LINK_PY"), $(basename "$MCP_REDIRECT_PY"), $(basename "$HANDSHAKE_SH"), $(basename "$WIFI_SCAN_SH")"
    echo "  -- last log lines --"
    for _f in "$ANCHOR/pax-link.log" "$LOGS_DIR/mcp-redirect.log" "$RUN_LOG"; do
        [ -f "$_f" ] && { echo "  [$(_basename "$_f")]"; tail -3 "$_f" | sed 's/^/    /'; }
    done
}

_basename() { printf '%s' "${1##*/}"; }

# --- verify (notebook cells 22-23) ---------------------------------------
# Re-checks every addressing and reports PASS/FAIL/SKIP per item with
# the actual value seen. Returns 0 only if every REQUIRED item passed;
# returns the number of failed required items otherwise (and the
# failing items are listed in the output). SKIP items are
# informational only and never fail the run: the VM daemon socket is
# not directly reachable from the phone (the VM accepts no inbound
# connections and its daemon binds 127.0.0.1 only) — the daemon link
# is verified instead by the "daemon connected in" line in
# pax-link.log, because the link direction is daemon -> phone.
do_verify() {
    echo "== autoruntime verify — anchor: $ANCHOR =="
    _pass=0; _fail=0; _skip=0
    _check() { # _check <name> <ok: 0/1> <detail>
        if [ "$2" = "0" ]; then _pass=$((_pass+1)); echo "[PASS] $1: $3";
        else _fail=$((_fail+1)); echo "[FAIL] $1: $3"; fi
    }
    _skip() { # _skip <name> <detail> — informational, never fails the run
        _skip=$((_skip+1)); echo "[SKIP] $1: $2"
    }
    # 1. Device endpoint listening on 127.0.0.1:18765 (the socket, phone-side)
    if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$DEVICE_PORT),timeout=3); s.close()" 2>/dev/null; then
        _check "device endpoint listening" 0 "ws://127.0.0.1:$DEVICE_PORT accepts connections"
    else
        _check "device endpoint listening" 1 "cannot connect to 127.0.0.1:$DEVICE_PORT — is the device link running?"
    fi
    # 2. MCP redirect health (its own /health live-checks the upstream)
    if command -v curl >/dev/null 2>&1; then
        _h="$(curl -sS -m 25 "http://127.0.0.1:$MCP_PORT/health" 2>/dev/null)"
        case "$_h" in
            *'"status": "ok"'*) _check "MCP redirect healthy" 0 "GET /health -> upstream ok" ;;
            *'"status": "down"'*) _check "MCP redirect healthy" 1 "GET /health -> upstream down: $(printf '%s' "$_h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('detail',''))" 2>/dev/null)" ;;
            *) _check "MCP redirect healthy" 1 "GET /health gave no usable answer — is the redirect running?" ;;
        esac
        # 3. Upstream gitMCP specific (AutoPoET) reachable
        _code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 "$UPSTREAM_MCP" 2>/dev/null)"
        if [ "$_code" = "200" ]; then
            _check "upstream gitMCP (specific) reachable" 0 "GET $UPSTREAM_MCP -> 200"
        else
            _check "upstream gitMCP (specific) reachable" 1 "GET $UPSTREAM_MCP -> ${_code:-no answer}"
        fi
        # 4. Upstream gitMCP generic (/docs) reachable
        _code="$(curl -s -o /dev/null -w '%{http_code}' -m 15 "$UPSTREAM_MCP_GENERIC" 2>/dev/null)"
        if [ "$_code" = "200" ]; then
            _check "upstream gitMCP (generic /docs) reachable" 0 "GET $UPSTREAM_MCP_GENERIC -> 200"
        else
            _check "upstream gitMCP (generic /docs) reachable" 1 "GET $UPSTREAM_MCP_GENERIC -> ${_code:-no answer}"
        fi
    else
        _skip "MCP redirect / upstream checks" "need curl (pkg install curl)"
    fi
    # 5. Folder watcher alive (the device link logs a watching line)
    if grep -q "watching $ANCHOR" "$LOGS_DIR/device-link.out.log" "$ANCHOR/pax-link.log" 2>/dev/null; then
        _check "folder watcher alive" 0 "device link is watching $ANCHOR"
    else
        _check "folder watcher alive" 1 "no 'watching $ANCHOR' line in the device-link logs yet"
    fi
    # 6. Log trigger (events are being recorded in pax-link.log)
    if [ -f "$ANCHOR/pax-link.log" ] && grep -q "DEVICE-LINK" "$ANCHOR/pax-link.log" 2>/dev/null; then
        _check "log trigger (pax-link.log)" 0 "pax-link.log has [DEVICE-LINK] lines"
    else
        _check "log trigger (pax-link.log)" 1 "no [DEVICE-LINK] lines in pax-link.log yet"
    fi
    # 7. MCP redirect log exists and has lines
    if [ -f "$LOGS_DIR/mcp-redirect.log" ] && [ -s "$LOGS_DIR/mcp-redirect.log" ]; then
        _check "log trigger (mcp-redirect.log)" 0 "logs/mcp-redirect.log exists and has lines"
    elif [ -f "$LOGS_DIR/mcp-redirect.log" ]; then
        _check "log trigger (mcp-redirect.log)" 1 "logs/mcp-redirect.log exists but is empty — no MCP request forwarded yet"
    else
        _check "log trigger (mcp-redirect.log)" 1 "no logs/mcp-redirect.log — is the redirect running?"
    fi
    # 8. Endpoints map written, with all four addressing sections
    if [ -f "$STATE_DIR/endpoints.json" ]; then
        if python3 -c "import json,sys; d=json.load(open('$STATE_DIR/endpoints.json')); assert all(k in d for k in ('urls','runtimes','vpn','log_triggers')), 'missing section'" 2>/dev/null; then
            _check "endpoints map written" 0 "$STATE_DIR/endpoints.json (urls, runtimes, vpn, log_triggers)"
        else
            _check "endpoints map written" 1 "$STATE_DIR/endpoints.json exists but is missing a section (urls/runtimes/vpn/log_triggers) — re-run link"
        fi
    else
        _check "endpoints map written" 1 "no $STATE_DIR/endpoints.json — run link first"
    fi
    # 9. Handshake script present (run on demand after an MCP tool call)
    if [ -f "$HANDSHAKE_SH" ]; then
        _check "handshake script present" 0 "$HANDSHAKE_SH"
    else
        _check "handshake script present" 1 "no $HANDSHAKE_SH — run link first"
    fi
    # 10. Wi-Fi scan script present (Termux:API; optional use)
    if [ -f "$WIFI_SCAN_SH" ]; then
        _check "wifi scan script present" 0 "$WIFI_SCAN_SH"
    else
        _check "wifi scan script present" 1 "no $WIFI_SCAN_SH — run link first"
    fi
    # 11. Daemon link: the VM daemon has connected in to the device endpoint
    if grep -q "daemon connected in\|connected to daemon" "$ANCHOR/pax-link.log" 2>/dev/null; then
        _check "daemon link (VM daemon connected)" 0 "pax-link.log shows a daemon connection — the live link is up"
    else
        _check "daemon link (VM daemon connected)" 1 "no daemon connection in pax-link.log yet — the daemon reconnects with backoff; check the daemon is up and PAX_DEVICE_ENDPOINT_URL is set to ws://<phone-tailnet-ip>:18765"
    fi
    # 12. Phone tailnet IP recorded (and how it was resolved)
    resolve_phone_ts_ip
    _check "phone tailnet IP recorded" 0 "$PHONE_MAGICDNS = $PHONE_TS_IP (via $PHONE_TS_IP_SOURCE)"
    # 13. VM daemon socket directly reachable — INFORMATIONAL ONLY.
    # The VM accepts no inbound connections and its daemon binds
    # 127.0.0.1:8765 only, so this is expected to fail from the phone.
    # It is recorded, never a failure, and never fabricated as a success.
    if python3 -c "import socket; s=socket.create_connection(('$VM_TS_IP',8765),timeout=5); s.close()" 2>/dev/null; then
        _skip "VM daemon socket directly reachable" "TCP connect to $VM_TS_IP:8765 succeeded (unexpected — the VM accepts no inbound connections; the link direction is daemon -> phone)"
    else
        _skip "VM daemon socket directly reachable" "TCP connect to $VM_TS_IP:8765 failed (expected — the VM accepts no inbound connections and its daemon binds 127.0.0.1 only; the link direction is daemon -> phone, see check 11)"
    fi
    # 14. Rollover state consistent: the files state/rollover.json
    # names must all exist. A missing one means a rollover was
    # interrupted or files were deleted by hand — re-run rollover
    # to repair (it resumes an in-progress rollover).
    _rstamp="$(current_stamp)"
    if [ -z "$_rstamp" ]; then
        _check "rollover state consistent" 0 "no rollover yet — legacy fixed file names in use"
    elif [ -f "$DEVICE_LINK_PY" ] && [ -f "$MCP_REDIRECT_PY" ] && [ -f "$HANDSHAKE_SH" ] && [ -f "$WIFI_SCAN_SH" ]; then
        _check "rollover state consistent" 0 "stamp $_rstamp — all four active files exist"
    else
        _check "rollover state consistent" 1 "stamp $_rstamp but an active file is missing — re-run rollover to repair"
    fi
    echo
    echo "Summary: $_pass PASS, $_fail FAIL, $_skip SKIP"
    if [ "$_fail" = "0" ]; then
        echo "Autoruntime healthy — everything is linked."
        return 0
    else
        echo "Autoruntime not fully healthy yet — see FAIL above."
        return "$_fail"
    fi
}

# --- stop (notebook cells 24-25) ----------------------------------------
do_stop() {
    stop_process "pax_mcp_redirect.py" "$PIDS_DIR/mcp-redirect.pid"
    stop_process "pax_device_link.py" "$PIDS_DIR/device-link.pid"
    log "autoruntime stopped (anchor $ANCHOR; logs and state kept)."
}

# --- start (notebook cells 14-17: start, in this order) -----------------
do_start() {
    log "autoruntime starting — anchor: $ANCHOR"
    step_install
    resolve_current_files
    write_embedded_scripts
    step_anchor
    step_device_link
    step_mcp_redirect
    log "--- endpoints (all anchored at $ANCHOR) ---"
    write_endpoints
    _pip="$(phone_ip)"
    log "device endpoint: ws://${_pip:-<phone-ip>}:$DEVICE_PORT (the daemon connects OUT to this; set PAX_DEVICE_ENDPOINT_URL to it on the daemon)"
    log "MCP redirect:    http://127.0.0.1:$MCP_PORT -> $UPSTREAM_MCP"
    log "daemon socket:   $DAEMON_WS (VM side)   webhook: $WEBHOOK_BASE/hook/$FOLDER_ID/$SESSION_ID (VM side)"
    log "autoruntime started. Run 'bash pax-autoruntime-full.sh status' or 'bash pax-autoruntime-full.sh verify'."
}

# --- ensure_log_triggers --------------------------------------------------
# The log files the double listener and the watcher depend on must
# exist and be written to. The device link creates pax-link.log when
# it starts and the redirect creates logs/mcp-redirect.log on its
# first forward; this makes sure both files exist (touch, never
# truncate) and records their paths in state/endpoints.json (which
# write_endpoints already writes). No second watcher is started —
# the device link's own watcher is the trigger.
ensure_log_triggers() {
    mkdir -p "$LOGS_DIR"
    touch "$ANCHOR/pax-link.log" "$LOGS_DIR/mcp-redirect.log" 2>/dev/null
    log "log triggers: $ANCHOR/pax-link.log, $LOGS_DIR/mcp-redirect.log (paths recorded in state/endpoints.json)."
}

# --- wait_for_daemon_link --------------------------------------------------
# Wait up to $1 seconds for the VM daemon to connect in to the device
# endpoint — the real signal that the daemon link is up. The daemon
# connects OUT to the phone (the phone never connects to the daemon:
# the VM accepts no inbound connections), and the device link logs
# "daemon connected in" when it does. Returns 0 if seen, 1 if not.
wait_for_daemon_link() {
    _wait="${1:-30}"
    _elapsed=0
    while [ "$_elapsed" -lt "$_wait" ]; do
        if grep -q "daemon connected in" "$ANCHOR/pax-link.log" 2>/dev/null; then
            log "daemon link: the VM daemon has connected in to the device endpoint."
            return 0
        fi
        sleep 2
        _elapsed=$((_elapsed + 2))
    done
    log "daemon link: no daemon connection seen in pax-link.log after ${_wait}s — the daemon reconnects with backoff; re-run verify later."
    return 1
}

# --- link (one one-time execution that links it all) ----------------------
# The one pass the user runs once on the phone in Termux:
#   1. installs the packages and writes the four embedded scripts
#      (only if missing; PAX_FORCE_WRITE=1 overwrites),
#   2. starts the device link and the MCP redirect,
#   3. writes the full addressing map to state/endpoints.json
#      (URLs, runtimes, VPN addressments, log triggers),
#   4. waits for the VM daemon to connect in (the daemon link),
#   5. ensures the log-file triggers exist,
#   6. prints the addressings, and runs the full verify.
# Exit 0 only if every required verify item passed; exit 1 with the
# failing items listed if any required item failed. The daemon's
# direct reachability from the phone is NOT a required item — the VM
# accepts no inbound connections and its daemon binds 127.0.0.1 only,
# so it is recorded as an informational check, never a failure.
do_link() {
    log "LINK — one-time execution: linking the whole autoruntime (anchor: $ANCHOR)"
    step_install
    resolve_current_files
    write_embedded_scripts
    step_anchor
    step_device_link
    step_mcp_redirect
    log "--- addressings (all anchored at $ANCHOR) ---"
    write_endpoints
    resolve_phone_ts_ip
    _pip="$(phone_ip)"
    log "MCP specific:  $UPSTREAM_MCP"
    log "MCP generic:   $UPSTREAM_MCP_GENERIC  (any public repo, on the fly)"
    log "MCP redirect:  http://127.0.0.1:$MCP_PORT  -> $UPSTREAM_MCP"
    log "MCP via VPN:   http://$PHONE_TS_IP:$MCP_PORT  (phone tailnet IP, via $PHONE_TS_IP_SOURCE)"
    log "device endpoint: ws://$PHONE_TS_IP:$DEVICE_PORT  (the daemon connects OUT to this)"
    log "device endpoint (wifi): ws://${_pip:-<phone-wifi-ip>}:$DEVICE_PORT"
    log "daemon socket: $DAEMON_WS  (VM side, VM-local only)"
    log "webhook:       $WEBHOOK_BASE/hook/$FOLDER_ID/$SESSION_ID  (VM side)"
    log "VPN: phone $PHONE_MAGICDNS = $PHONE_TS_IP ($PHONE_TS_IP_SOURCE); VM tailnet $VM_TS_IP"
    log "Colab notebook: $COLAB_NOTEBOOK_ID (its socket cell predates the device link — recorded in endpoints.json, not fixed)"
    ensure_log_triggers
    wait_for_daemon_link 30 || true
    log "--- verify ---"
    do_verify
    _rc=$?
    if [ "$_rc" = "0" ]; then
        log "LINK COMPLETE: every required check passed. The whole autoruntime is linked."
    else
        log "LINK INCOMPLETE: $_rc required check(s) failed — see FAIL above. Re-run 'bash pax-autoruntime-full.sh link' or 'verify' after fixing them."
    fi
    return $_rc
}

# --- rollover: the self-aware update --------------------------------------
# The ephemeral persistent loops (device link, MCP redirect, the VM
# daemon, the pulse) cannot be stopped by closing the terminal, and a
# file with the same name is never re-propagated — every file must be
# uniquely named every time, or it will not run. Drive makes it
# worse: uploading a file with a duplicate name writes it as
# "name (1)" instead of replacing the original, so a same-name upload
# never replaces the original. So an update cannot be "the same file,
# new content". It has to be a rollover: a whole new set of files
# with new names, and the running services moved over to them.
#
# What rollover does, in order (one execution, `bash ... rollover`):
#   1. One UTC stamp for the whole deployment (YYYYMMDD-HHMMSS).
#      All four scripts get new names with that stamp, same root and
#      extension (pax_device_link-<stamp>.py, ...), so the set is one
#      deployment and the wildcard cleanup (root + * + extension)
#      can find every old copy, including Drive "(1)" duplicates.
#   2. A state/rollover.json marker is written BEFORE any old service
#      is stopped, so if the run is interrupted the next run sees the
#      in-progress rollover and resumes it instead of leaving two
#      half-running sets. The marker records the stamp, the SHA-256
#      of THIS .sh (the deployment), the old -> new name map, and the
#      status. A second run with the same .sh and a completed
#      rollover is a no-op ("already on the latest rollover").
#   3. The new files are written and syntax-checked (ast.parse for
#      the .py files, bash -n for the .sh files). If a new file does
#      not parse, the old services are NOT touched and the run exits
#      1 with the new files in place for a retry.
#   4. Each new service is PROBED before the old one is stopped: it
#      is started from its new file on a TEMPORARY port (device
#      endpoint +2, redirect +2) and checked to answer there. The
#      temp port is used because the new service cannot bind the real
#      port while the old service holds it — so the probe proves the
#      new code launches and answers, without touching the old one.
#      If a probe fails, the old service is NOT stopped and the run
#      exits 1.
#   5. The old services are stopped, the new ones are started from
#      the new files on the real ports, and each is confirmed alive
#      and answering (device endpoint on 18765, MCP redirect /health
#      on 18766). The daemon is then given time to reconnect in
#      (it reconnects with backoff on its own). Only after the new
#      services are confirmed are the old files removed.
#   6. The log files are carried over, NOT doubled: the new services
#      append to the SAME logs (pax-link.log, logs/mcp-redirect.log,
#      logs/autoruntime.log, logs/device-link.out.log). This saves
#      space on install.
#   7. The old files are removed: for each deployed file, every file
#      matching root + "*" + extension is deleted EXCEPT the new
#      file just written — and never the running .sh itself. This
#      removes the legacy names, older versioned copies, and any
#      Drive "(1)" duplicates.
#   8. state/endpoints.json is rewritten with the new file names
#      (addressings unchanged unless a value actually changed) and
#      the rollover stamp.
# The VM daemon side is NOT rolled over here: this script runs on
# the phone (Termux) and cannot restart the VM's systemd services.
# The VM side needs its own deploy_pax_pipeline.sh rollover (same
# stamp + migrate + wildcard cleanup for pax_socket.py and
# pax_folder_watcher.py under systemd). Nothing is ever lost or
# dropped on the phone side: the process moves to the new construct
# while running, and if the new service cannot be confirmed the old
# files are left on disk (the run exits 1 and the marker records the
# failure, so a re-run resumes it).
#
# One honest limit: the new service cannot bind the real port until
# the old one releases it, so there is a brief handover gap (a few
# seconds) between stopping the old and starting the new. The VM
# daemon reconnects with backoff on its own, and the device link's
# watcher logs every folder event to pax-link.log, so no file change
# is lost — only a folder event that happens inside the gap is not
# re-reported as an event (the file itself is still there). The
# probe (step 4) is what makes the gap safe: the new code is proven
# to launch and answer before the old is ever stopped.

_file_sha() { # _file_sha <path> — SHA-256 of a file, or "unavailable"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" 2>/dev/null | awk '{print "md5:"$1}'
    else
        printf 'unavailable'
    fi
}

_write_rollover_json() { # _write_rollover_json <status> — write state/rollover.json
    # Reads ROLLOVER_* from the environment (set by do_rollover) and
    # ROLLOVER_REMOVED_FILE (one removed path per line, or /dev/null).
    ROLLOVER_STATUS="$1" python3 - "$ROLLOVER_JSON" <<'PYEOF'
import json, os, sys
from datetime import datetime, timezone
path = sys.argv[1]
removed = []
try:
    with open(os.environ.get("ROLLOVER_REMOVED_FILE", "/dev/null")) as f:
        removed = [line.strip() for line in f if line.strip()]
except OSError:
    removed = []
data = {
    "stamp": os.environ.get("ROLLOVER_STAMP", ""),
    "created_at": os.environ.get("ROLLOVER_CREATED_AT", ""),
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": os.environ.get("ROLLOVER_STATUS", ""),
    "deployment_sha256": os.environ.get("ROLLOVER_SELF_SHA", ""),
    "previous_stamp": os.environ.get("ROLLOVER_PREV_STAMP", "") or None,
    "files": {
        "device_link": os.environ.get("ROLLOVER_NEW_DL", ""),
        "mcp_redirect": os.environ.get("ROLLOVER_NEW_MCP", ""),
        "handshake": os.environ.get("ROLLOVER_NEW_HS", ""),
        "wifi_scan": os.environ.get("ROLLOVER_NEW_WIFI", ""),
    },
    "previous_files": {
        "device_link": os.environ.get("ROLLOVER_OLD_DL", ""),
        "mcp_redirect": os.environ.get("ROLLOVER_OLD_MCP", ""),
        "handshake": os.environ.get("ROLLOVER_OLD_HS", ""),
        "wifi_scan": os.environ.get("ROLLOVER_OLD_WIFI", ""),
    },
    "logs_carried_over": True,
    "logs": ["pax-link.log", "logs/mcp-redirect.log", "logs/autoruntime.log", "logs/device-link.out.log"],
    "removed": removed,
    "note": "Self-aware rollover: one UTC stamp for the whole deployment; the running services were moved to the new file names; the same log files are appended to (not doubled); old files (root + * + extension, including Drive '(1)' duplicates) were removed after the new services were confirmed alive. The VM daemon side is NOT rolled over by this script.",
}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

_cleanup_old_files() { # _cleanup_old_files <root> <ext> <keep-name>
    # Delete every file matching root + * + ext EXCEPT the keep-name
    # and never the running .sh itself. The removed paths are appended
    # to $ROLLOVER_REMOVED_FILE for the marker.
    _root="$1"; _ext="$2"; _keep="$3"
    _self_base="$(basename "${BASH_SOURCE[0]:-$0}")"
    for _f in "$ANCHOR/${_root}"*"${_ext}"; do
        [ -e "$_f" ] || continue
        _base="$(basename "$_f")"
        [ "$_base" = "$_keep" ] && continue
        [ "$_base" = "$_self_base" ] && continue
        if rm -f "$_f"; then
            log "rollover: removed old file: $_base"
            printf '%s\n' "$_f" >> "$ROLLOVER_REMOVED_FILE"
        else
            log "rollover: WARNING: could not remove old file: $_base"
        fi
    done
}

_check_device_endpoint() { # true if the device endpoint answers on 127.0.0.1:$1
    python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$1),timeout=3); s.close()" 2>/dev/null
}

_check_mcp_info() { # true if the redirect answers GET / with 200 on 127.0.0.1:$1
    command -v curl >/dev/null 2>&1 || return 1
    [ "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "http://127.0.0.1:$1/" 2>/dev/null)" = "200" ]
}

_check_mcp_health() { # true if the redirect /health reports ok on 127.0.0.1:$MCP_PORT
    command -v curl >/dev/null 2>&1 || return 1
    _h="$(curl -sS -m 25 "http://127.0.0.1:$MCP_PORT/health" 2>/dev/null)"
    case "$_h" in *'"status": "ok"'*) return 0 ;; *) return 1 ;; esac
}

_rollover_probe() { # _rollover_probe <kind> <newfile> — probe the new service on a temp port
    # kind: device-link | mcp-redirect. The temp port (real port + 2)
    # is used because the new service cannot bind the real port while
    # the old service holds it. Returns 0 if the new service launched
    # and answered on its temp port, 1 otherwise. The probe process
    # is always stopped before returning (it was only a probe).
    _pk="$1"; _pf="$2"
    case "$_pk" in
        device-link)
            _ppidfile="$PIDS_DIR/device-link.probe.pid"; _plog="$LOGS_DIR/device-link.out.log"
            _pport=$((DEVICE_PORT + 2))
            ;;
        mcp-redirect)
            _ppidfile="$PIDS_DIR/mcp-redirect.probe.pid"; _plog="$LOGS_DIR/mcp-redirect.out.log"
            _pport=$((MCP_PORT + 2))
            ;;
        *) log "rollover: probe: unknown kind $_pk"; return 1 ;;
    esac
    rm -f "$_ppidfile"
    mkdir -p "$LOGS_DIR"
    case "$_pk" in
        device-link)
            nohup python3 "$ANCHOR/$_pf" --serve --dir "$ANCHOR" --port "$_pport" >> "$_plog" 2>&1 &
            ;;
        mcp-redirect)
            nohup python3 "$ANCHOR/$_pf" --dir "$ANCHOR" --port "$_pport" >> "$_plog" 2>&1 &
            ;;
    esac
    _ppid=$!
    echo "$_ppid" > "$_ppidfile"
    _ok=1
    _i=0
    while [ "$_i" -lt 8 ]; do
        sleep 1; _i=$((_i+1))
        if ! is_alive "$_ppid"; then break; fi
        case "$_pk" in
            device-link) _check_device_endpoint "$_pport" && { _ok=0; break; } ;;
            mcp-redirect) _check_mcp_info "$_pport" && { _ok=0; break; } ;;
        esac
    done
    if is_alive "$_ppid"; then
        kill "$_ppid" 2>/dev/null; sleep 1
        is_alive "$_ppid" && kill -9 "$_ppid" 2>/dev/null
    fi
    rm -f "$_ppidfile"
    if [ "$_ok" = "0" ]; then
        log "rollover: probe: new $_pk launched and answered on temp port $_pport — it will start on the real port after the handover."
        return 0
    fi
    log "ERROR: rollover: probe: new $_pk did not answer on temp port $_pport — see $_plog. Old service untouched."
    return 1
}

_stop_old_service() { # _stop_old_service <name> <pidfile> <old-file-basename>
    # Stop by pid file, then kill any straggler still running from the
    # OLD file path (the new file has a different name, so it cannot
    # match). Safe to call when the old service is already stopped.
    _name="$1"; _pidfile="$2"; _oldfile="$3"
    stop_process "$_name" "$_pidfile"
    if command -v pgrep >/dev/null 2>&1 && pgrep -f "python3 $ANCHOR/$_oldfile" >/dev/null 2>&1; then
        log "rollover: old $_name still running without a pid file — stopping it by path."
        pkill -f "python3 $ANCHOR/$_oldfile" 2>/dev/null || true
        sleep 1
        pgrep -f "python3 $ANCHOR/$_oldfile" >/dev/null 2>&1 && pkill -9 -f "python3 $ANCHOR/$_oldfile" 2>/dev/null || true
    fi
}

do_rollover() {
    log "ROLLOVER — self-aware migration: moving the runtime to new file names (anchor: $ANCHOR)"
    mkdir -p "$ANCHOR" "$LOGS_DIR" "$STATE_DIR" "$PIDS_DIR"
    command -v python3 >/dev/null 2>&1 || die "python3 not found — run start first (it installs python3)."
    _self="${BASH_SOURCE[0]:-$0}"
    _self_sha="$(_file_sha "$_self")"
    _created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _removed_file="$STATE_DIR/rollover-removed.txt"
    : > "$_removed_file" 2>/dev/null || _removed_file="/dev/null"
    # --- 1. stamp: reuse an in-progress/failed one from the same
    # deployment, else a fresh UTC stamp; no-op if already latest.
    _stamp=""; _prev_stamp=""
    if [ -f "$ROLLOVER_JSON" ]; then
        _prev_stamp="$(_rollover_field stamp)"
        _prev_status="$(_rollover_field status)"
        _prev_sha="$(_rollover_field deployment_sha256)"
        if [ "$_prev_status" = "complete" ] && [ -n "$_self_sha" ] && [ "$_prev_sha" = "$_self_sha" ]; then
            _missing=0
            for _lf in device_link mcp_redirect handshake wifi_scan; do
                case "$_lf" in
                    device_link) _lf_legacy="pax_device_link.py" ;;
                    mcp_redirect) _lf_legacy="pax_mcp_redirect.py" ;;
                    handshake) _lf_legacy="pax_gemini_handshake.sh" ;;
                    wifi_scan) _lf_legacy="termux-wifi-scan.sh" ;;
                esac
                _cur="$(current_name "$_lf" "$_lf_legacy")"
                [ -f "$ANCHOR/$_cur" ] || _missing=1
            done
            if [ "$_missing" = "0" ]; then
                log "rollover: already on the latest rollover (stamp $_prev_stamp) — nothing to do."
                return 0
            fi
            log "rollover: marker says complete (stamp $_prev_stamp) but an active file is missing — re-rolling with a fresh stamp."
        elif { [ "$_prev_status" = "in-progress" ] || [ "$_prev_status" = "failed" ]; } && [ -n "$_self_sha" ] && [ "$_prev_sha" = "$_self_sha" ]; then
            log "rollover: resuming interrupted rollover (stamp $_prev_stamp, status $_prev_status) — same deployment."
            _stamp="$_prev_stamp"
        elif [ -n "$_prev_stamp" ]; then
            log "rollover: previous rollover was stamp $_prev_stamp (status ${_prev_status:-unknown}) — starting a fresh one."
        fi
    fi
    if [ -z "$_stamp" ]; then
        _stamp="$(date -u +%Y%m%d-%H%M%S)"
    fi
    # --- 2. old -> new name map (one stamp for the whole deployment).
    _old_dl="$(current_name device_link pax_device_link.py)"
    _old_mcp="$(current_name mcp_redirect pax_mcp_redirect.py)"
    _old_hs="$(current_name handshake pax_gemini_handshake.sh)"
    _old_wifi="$(current_name wifi_scan termux-wifi-scan.sh)"
    _new_dl="pax_device_link-$_stamp.py"
    _new_mcp="pax_mcp_redirect-$_stamp.py"
    _new_hs="pax_gemini_handshake-$_stamp.sh"
    _new_wifi="termux-wifi-scan-$_stamp.sh"
    log "rollover: stamp $_stamp"
    log "rollover: $_old_dl -> $_new_dl"
    log "rollover: $_old_mcp -> $_new_mcp"
    log "rollover: $_old_hs -> $_new_hs"
    log "rollover: $_old_wifi -> $_new_wifi"
    export ROLLOVER_STAMP="$_stamp" ROLLOVER_CREATED_AT="$_created_at"
    export ROLLOVER_SELF_SHA="$_self_sha" ROLLOVER_PREV_STAMP="$_prev_stamp"
    export ROLLOVER_OLD_DL="$_old_dl" ROLLOVER_NEW_DL="$_new_dl"
    export ROLLOVER_OLD_MCP="$_old_mcp" ROLLOVER_NEW_MCP="$_new_mcp"
    export ROLLOVER_OLD_HS="$_old_hs" ROLLOVER_NEW_HS="$_new_hs"
    export ROLLOVER_OLD_WIFI="$_old_wifi" ROLLOVER_NEW_WIFI="$_new_wifi"
    export ROLLOVER_REMOVED_FILE="$_removed_file"
    # --- 3. write the new files, then the in-progress marker BEFORE
    # stopping any old service. (write_embedded_scripts skips files
    # that already exist — on a resume the new files are already
    # there with identical content.)
    write_embedded_scripts "-$_stamp"
    for _nf in "$_new_dl" "$_new_mcp" "$_new_hs" "$_new_wifi"; do
        [ -f "$ANCHOR/$_nf" ] || die "rollover: new file $_nf was not written — aborting, old services untouched."
    done
    _write_rollover_json "in-progress"
    log "rollover: marker written ($ROLLOVER_JSON, status in-progress) — a re-run will resume this rollover."
    # --- 4. pre-flight: the new files must parse before anything old
    # is touched. ast.parse (not py_compile) so no __pycache__ is
    # created in the anchor folder.
    if ! python3 -c "import ast,sys; [ast.parse(open(f).read()) for f in sys.argv[1:]]" "$ANCHOR/$_new_dl" "$ANCHOR/$_new_mcp" 2>/dev/null; then
        log "ERROR: rollover: new python files do not parse — old services untouched. Fix the deployment and re-run rollover."
        _write_rollover_json "failed"
        return 1
    fi
    if ! bash -n "$ANCHOR/$_new_hs" "$ANCHOR/$_new_wifi" 2>/dev/null; then
        log "ERROR: rollover: new shell files do not parse (bash -n) — old services untouched. Fix the deployment and re-run rollover."
        _write_rollover_json "failed"
        return 1
    fi
    log "rollover: pre-flight passed — new files parse."
    # --- 5. probe each new service on a temp port before stopping
    # the old one. The new service cannot bind the real port while
    # the old one holds it, so the probe uses real port + 2.
    if ! _rollover_probe device-link "$_new_dl"; then
        _write_rollover_json "failed"
        return 1
    fi
    if ! _rollover_probe mcp-redirect "$_new_mcp"; then
        _write_rollover_json "failed"
        return 1
    fi
    # --- 6. handover: stop the old services, then start the new ones
    # from the new files on the real ports. The globals are pointed
    # at the new files first, so step_device_link / step_mcp_redirect
    # (and status / verify after this) all use the new names.
    _stop_old_service "pax_mcp_redirect.py" "$PIDS_DIR/mcp-redirect.pid" "$_old_mcp"
    _stop_old_service "pax_device_link.py" "$PIDS_DIR/device-link.pid" "$_old_dl"
    DEVICE_LINK_PY="$ANCHOR/$_new_dl"
    MCP_REDIRECT_PY="$ANCHOR/$_new_mcp"
    HANDSHAKE_SH="$ANCHOR/$_new_hs"
    WIFI_SCAN_SH="$ANCHOR/$_new_wifi"
    step_device_link || { log "ERROR: rollover: new device link failed to start — old files left on disk; re-run rollover to retry."; _write_rollover_json "failed"; return 1; }
    step_mcp_redirect || { log "ERROR: rollover: new MCP redirect failed to start — old files left on disk; re-run rollover to retry."; _write_rollover_json "failed"; return 1; }
    # --- 7. confirm the new services are alive and answering on the
    # real ports. Only then is anything old removed.
    _dl_ok=0; _mcp_ok=0
    _i=0
    while [ "$_i" -lt 10 ]; do
        sleep 1; _i=$((_i+1))
        _check_device_endpoint "$DEVICE_PORT" && { _dl_ok=1; break; }
    done
    _i=0
    while [ "$_i" -lt 25 ]; do
        sleep 1; _i=$((_i+1))
        _check_mcp_health && { _mcp_ok=1; break; }
    done
    if [ "$_dl_ok" != "1" ]; then
        log "ERROR: rollover: new device link is not answering on $DEVICE_PORT — old files left on disk; re-run rollover to retry."
        _write_rollover_json "failed"
        return 1
    fi
    if [ "$_mcp_ok" != "1" ]; then
        log "ERROR: rollover: new MCP redirect /health is not ok on $MCP_PORT — old files left on disk; re-run rollover to retry."
        _write_rollover_json "failed"
        return 1
    fi
    log "rollover: new services confirmed alive and answering (device endpoint $DEVICE_PORT, MCP redirect /health $MCP_PORT)."
    # The daemon reconnects in to the new device link on its own
    # backoff; give it up to 60s and report, but do not fail the
    # rollover on it — the link direction is daemon -> phone and the
    # daemon will keep retrying.
    wait_for_daemon_link 60 || true
    # --- 8. logs are carried over, not doubled: the new services
    # append to the SAME log files. Nothing to create — just record it.
    ensure_log_triggers
    log "rollover: log files carried over (same pax-link.log, logs/mcp-redirect.log, logs/autoruntime.log, logs/device-link.out.log) — not doubled."
    # --- 9. remove the old files (root + * + extension), except the
    # new file and never the running .sh. Only now, after the new
    # services are confirmed alive.
    _cleanup_old_files "pax_device_link" ".py" "$_new_dl"
    _cleanup_old_files "pax_mcp_redirect" ".py" "$_new_mcp"
    _cleanup_old_files "pax_gemini_handshake" ".sh" "$_new_hs"
    _cleanup_old_files "termux-wifi-scan" ".sh" "$_new_wifi"
    # --- 10. mark complete and rewrite the endpoints map with the
    # new file names (addressings unchanged unless a value changed).
    _write_rollover_json "complete"
    write_endpoints >/dev/null 2>&1 || log "rollover: note: write_endpoints had a problem — run link to rewrite state/endpoints.json."
    log "ROLLOVER COMPLETE: stamp $_stamp — services now run from $_new_dl and $_new_mcp; logs carried over; old files removed."
    log "rollover: run 'bash pax-autoruntime-full.sh status' or 'verify' to confirm the whole runtime."
    return 0
}

# --- main ----------------------------------------------------------------
# --- handshake / wifi (on-demand commands) ------------------------------
do_handshake() { # do_handshake <mcp-tool> [note...] — run the handshake script
    [ -f "$HANDSHAKE_SH" ] || die "$(basename "$HANDSHAKE_SH") not found in $ANCHOR — run start first (it writes the embedded scripts)."
    bash "$HANDSHAKE_SH" "$@"
}

do_wifi() { # run the Wi-Fi scan (needs Termux:API)
    [ -f "$WIFI_SCAN_SH" ] || die "$(basename "$WIFI_SCAN_SH") not found in $ANCHOR — run start first."
    bash "$WIFI_SCAN_SH"
}

# --- main ----------------------------------------------------------------
case "${1:-start}" in
    start)     do_start ;;
    link)      do_link; exit $? ;;
    rollover)  do_rollover; exit $? ;;
    status)    do_status ;;
    verify)    do_verify; exit $? ;;
    stop)      do_stop ;;
    restart)   do_stop; sleep 1; do_start ;;
    handshake) shift; do_handshake "$@" ;;
    wifi)      do_wifi ;;
    *) echo "usage: bash pax-autoruntime-full.sh [start|link|rollover|status|verify|stop|restart|handshake <mcp-tool> [note...]|wifi]"; exit 1 ;;
esac
