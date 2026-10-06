#!/usr/bin/env python3
"""Hyprland IPC shim: translate legacy dispatch commands into the Lua form.

WHY THIS EXISTS
---------------
Waybar's `hyprland/workspaces` module has the legacy hyprlang dispatch strings
compiled in. Read straight out of the binary (`strings $(command -v waybar)`):

    dispatch workspace
    dispatch workspace name:
    dispatch focusworkspaceoncurrentmonitor
    dispatch focusworkspaceoncurrentmonitor name:
    dispatch togglespecialworkspace

Hyprland 0.56 with a pure-Lua config parses dispatch arguments as Lua, so every
one of those is a syntax error. Verified by writing the exact bytes waybar writes
to the real socket:

    dispatch workspace 3
    -> error: [string "return hl.dispatch(workspace 3)"]:1: ')' expected near '3'

So clicking any workspace pill was a silent no-op.

WHY NOT FIX IT IN WAYBAR'S CONFIG
---------------------------------
  * `on-click: activate` is the only thing that module honours. Pointing it at a
    shell command makes waybar attach NO handler at all — proven with an
    invocation log that stayed empty, and visible as the pointer cursor
    disappearing from the pills. Strictly worse than broken.
  * A Lua shim cannot rescue the built-in either: `hl.dispatch(workspace 3)` can
    never parse, because `f 3` is not valid Lua (only `f "str"` and `f{...}` are).
  * Hyprland has no legacy-dispatch compatibility option; `ecosystem` only
    exposes enforce_permissions / no_donation_nag / no_update_news.
  * waybar 0.15.0-3 is the newest in the Arch repos, so there is no upstream fix
    to wait for.
  * Replacing the module with custom pills DOES work, but it changes the bar's
    appearance: `hyprland/workspaces` renders `#workspaces > button`, while a
    group renders `#workspaces > widget > #custom-wsN`, i.e. a label one level
    deeper, without the theme-level min-width/min-height/padding a GTK button
    carries.

So the translation happens in the transport instead, leaving waybar's config and
CSS byte-identical.

HOW IT WORKS
------------
Waybar locates Hyprland by building $XDG_RUNTIME_DIR/hypr/$SIG/.socket{,2}.sock
from $HYPRLAND_INSTANCE_SIGNATURE. This listens on a parallel directory with the
same two socket names and is given to waybar via that env var. Requests are
rewritten if they match a known-legacy form and forwarded verbatim otherwise;
the .socket2.sock event stream is piped through untouched.

Deliberately narrow: only the exact legacy forms above are rewritten. Anything
else — including commands already using the Lua form — is passed through byte for
byte, so this cannot break another module.
"""

import os
import re
import socket
import sys
import threading

SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
if not SIG:
    sys.exit("HYPRLAND_INSTANCE_SIGNATURE is not set — is Hyprland running?")

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
REAL_DIR = os.path.join(RUNTIME, "hypr", SIG)
PROXY_DIR = os.path.join(RUNTIME, "hypr", f"{SIG}-shim")

REAL_CMD = os.path.join(REAL_DIR, ".socket.sock")
REAL_EVT = os.path.join(REAL_DIR, ".socket2.sock")
PROXY_CMD = os.path.join(PROXY_DIR, ".socket.sock")
PROXY_EVT = os.path.join(PROXY_DIR, ".socket2.sock")

VERBOSE = os.environ.get("HYPR_IPC_SHIM_VERBOSE") == "1"


def log(*a):
    if VERBOSE:
        print("[hypr-ipc-shim]", *a, file=sys.stderr, flush=True)


# ── Translation table ──────────────────────────────────────────────────────
# Each entry: (compiled pattern, builder(match) -> replacement payload).
# Patterns are anchored and only match the legacy spellings; a `name:` variant is
# handled separately because a named workspace is a Lua string, not a number.

def _ws_lua(target: str) -> str:
    """Build the Lua dispatch for a workspace target.

    A bare integer goes through as a number; anything else is quoted as a Lua
    string. Quoting matters: `name:` targets are arbitrary text.
    """
    if re.fullmatch(r"-?\d+", target):
        return f"hl.dsp.focus({{workspace = {target}}})"
    escaped = target.replace("\\", "\\\\").replace('"', '\\"')
    return f'hl.dsp.focus({{workspace = "{escaped}"}})'


RULES = [
    # dispatch workspace name:foo   /  dispatch workspace 3
    (re.compile(r"^(?P<p>/?)dispatch\s+workspace\s+(?:name:)?(?P<t>\S+)\s*$"),
     lambda m: f"{m.group('p')}dispatch {_ws_lua(m.group('t'))}"),
    # focusworkspaceoncurrentmonitor — same target semantics for a single monitor
    (re.compile(r"^(?P<p>/?)dispatch\s+focusworkspaceoncurrentmonitor\s+(?:name:)?(?P<t>\S+)\s*$"),
     lambda m: f"{m.group('p')}dispatch {_ws_lua(m.group('t'))}"),
    # togglespecialworkspace [name]
    (re.compile(r"^(?P<p>/?)dispatch\s+togglespecialworkspace\s*(?P<t>\S*)\s*$"),
     lambda m: (f"{m.group('p')}dispatch hl.dsp.workspace.toggle_special("
                f'"{m.group("t")}")' if m.group("t")
                else f"{m.group('p')}dispatch hl.dsp.workspace.toggle_special()")),
]


def translate(payload: bytes) -> bytes:
    try:
        text = payload.decode()
    except UnicodeDecodeError:
        return payload
    for pattern, build in RULES:
        m = pattern.match(text)
        if m:
            new = build(m)
            log(f"rewrite {text!r} -> {new!r}")
            return new.encode()
    return payload


# ── Plumbing ───────────────────────────────────────────────────────────────

def handle_command(client: socket.socket):
    """One request/response round trip on .socket.sock."""
    try:
        client.settimeout(5)
        payload = client.recv(65536)
        if not payload:
            return
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as upstream:
            upstream.settimeout(5)
            upstream.connect(REAL_CMD)
            upstream.sendall(translate(payload))
            # Hyprland closes after responding; read until EOF.
            while True:
                chunk = upstream.recv(65536)
                if not chunk:
                    break
                client.sendall(chunk)
    except Exception as e:  # never let one bad client kill the shim
        log("command error:", e)
    finally:
        try:
            client.close()
        except OSError:
            pass


def handle_event(client: socket.socket):
    """Pipe the event stream through untouched. Long-lived."""
    try:
        upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        upstream.connect(REAL_EVT)
    except Exception as e:
        log("event connect failed:", e)
        client.close()
        return

    def pump(src, dst):
        try:
            while True:
                data = src.recv(65536)
                if not data:
                    break
                dst.sendall(data)
        except Exception:
            pass
        finally:
            for s in (src, dst):
                try:
                    s.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass

    # Events only flow upstream -> client, but pump both directions so a client
    # disconnect tears the pair down promptly.
    threading.Thread(target=pump, args=(upstream, client), daemon=True).start()
    threading.Thread(target=pump, args=(client, upstream), daemon=True).start()


def serve(path: str, handler):
    if os.path.exists(path):
        os.unlink(path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    srv.listen(64)
    log("listening on", path)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handler, args=(conn,), daemon=True).start()


def main():
    for p in (REAL_CMD, REAL_EVT):
        if not os.path.exists(p):
            sys.exit(f"real Hyprland socket missing: {p}")

    os.makedirs(PROXY_DIR, exist_ok=True)
    print(f"[hypr-ipc-shim] proxying {PROXY_DIR} -> {REAL_DIR}", file=sys.stderr, flush=True)
    print(f"[hypr-ipc-shim] point clients at "
          f"HYPRLAND_INSTANCE_SIGNATURE={SIG}-shim", file=sys.stderr, flush=True)

    threading.Thread(target=serve, args=(PROXY_EVT, handle_event), daemon=True).start()
    serve(PROXY_CMD, handle_command)


if __name__ == "__main__":
    main()
