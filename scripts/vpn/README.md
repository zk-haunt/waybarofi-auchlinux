# VPN Setup (WireGuard + Waybar module)

How to get a VPN working on this system, starting from nothing.

## What you're working with

**A VPN** encrypts your traffic and routes it through a server somewhere else.
Your ISP then sees only "encrypted traffic to that server" instead of which
sites you visit, and those sites see the server's IP address instead of your
home one.

**WireGuard** is the protocol this setup uses — fast, modern, and configured by
a single small text file containing cryptographic keys.

**The waybar module** ([`vpn.sh`](vpn.sh))
is an indicator and an on/off switch. It does **not** provide a VPN. It watches
NetworkManager for WireGuard connections and shows:

| State | Appearance |
|---|---|
| No profile configured | Module hidden entirely |
| Profile exists, disconnected | Dim/grey icon — click to connect |
| Connected | Green icon — click to disconnect |

If you've never seen the module, that's the first row: it's correctly hiding
because you have nothing configured yet.

## What you actually need

**A `.conf` file from a VPN provider.** This is the only real prerequisite and
nothing on your machine can substitute for it. Everything is already installed
and wired up.

Options:

- **ProtonVPN** — has a free tier, gives you WireGuard config files. Easiest
  way to try the whole thing end to end.
- **Mullvad** — flat monthly fee, no account details required, strong privacy
  reputation.
- **IVPN** — similar model to Mullvad.
- **Your own server** — run WireGuard on a rented VPS. Cheapest long-term and
  fully under your control, but real setup work.

All of them have a "download WireGuard configuration" step in their account
dashboard where you pick a country and get a file.

## Step by step

### 1. Get the config file

From your provider's dashboard, download a WireGuard config. It'll be a small
text file, usually named something like `mullvad-de1.conf` or
`protonvpn-NL.conf`. Save it to `~/Downloads`.

It looks roughly like this inside — keys are secrets, don't share them:

```ini
[Interface]
PrivateKey = <your private key>
Address = 10.x.x.x/32
DNS = 10.x.x.x

[Peer]
PublicKey = <server public key>
AllowedIPs = 0.0.0.0/0
Endpoint = 203.0.113.5:51820
```

### 2. Import it into NetworkManager

```bash
nmcli connection import type wireguard file ~/Downloads/yourfile.conf
```

The connection is named after the filename — `mullvad-de1.conf` becomes a
profile called `mullvad-de1`. Import it once; it persists across reboots.

**Do not use nm-applet's "Add a VPN connection" dialog.** Its dropdown lists
only plugin-based VPN types (OpenVPN, vpnc, …) and will be empty unless you've
installed those plugin packages. WireGuard never appears there even though
NetworkManager supports it natively, because a WireGuard connection is defined
by a key file rather than a form. Importing is the only supported path.

### 3. Check it registered

```bash
nmcli -t -f NAME,TYPE connection show | grep wireguard
```

Your profile should be listed. The waybar module picks it up within about five
seconds — no restart needed — and appears in its dim "disconnected" state.

### 4. Connect

Click the VPN icon in the waybar status pill. It turns green.

Or from the terminal:

```bash
nmcli connection up <profile-name>
```

### 5. Verify it's actually working

Check your public IP — it should be the VPN server's, not your own:

```bash
curl -s https://ifconfig.me
```

Run this before and after connecting. If the number doesn't change, traffic
isn't going through the tunnel.

Also confirm the interface exists:

```bash
ip -br addr show | grep -i wg
```

### 6. Disconnect

Click the icon again, or:

```bash
nmcli connection down <profile-name>
```

## Managing profiles

```bash
# list all VPN profiles
nmcli -t -f NAME,TYPE connection show | grep wireguard

# which one is active right now
nmcli -t -f NAME,TYPE connection show --active | grep wireguard

# remove one permanently
nmcli connection delete <profile-name>
```

You can import several configs (different countries) — the module shows the
first one it finds and toggles that. To switch countries, connect the one you
want from nm-applet's VPN Connections submenu.

## Troubleshooting

**Module doesn't appear at all.** No WireGuard profile is configured. Run the
`nmcli ... show | grep wireguard` check above; if it's empty, the import didn't
happen.

**Module shows green but websites still see your real IP.** WireGuard is
connectionless, so the interface reports "up" as soon as it's configured even
if the server is unreachable. The module reflects interface state, not whether
traffic is really flowing. Use the `curl ifconfig.me` check — that's the
authoritative test.

**Import fails.** The file is malformed or truncated. Re-download it, and check
it has both an `[Interface]` and a `[Peer]` section.

**Nothing happens when clicking.** Confirm the script is executable and runs:

```bash
~/.config/waybar/scripts/vpn.sh
```

It should print JSON. If it prints nothing or errors, the deploy is broken —
run `./scripts/apply-config.sh`.

## Note: Tailscale is a different thing (and is no longer installed here)

**This machine ran Tailscale until 2026-10-02; it does not any more.** If you are
debugging the waybar module and looking for a `tailscale0` interface, there isn't
one. It was removed because its incoming shields were down, meaning any device on
the tailnet could reach this laptop.

Kept here because the distinction still matters if you ever reinstall it:
Tailscale is a *mesh* VPN — it privately links your own devices to each other, so
your phone can reach your laptop as if they shared a network. It is **not** a
privacy VPN and does not hide your traffic from your ISP, which is what the
WireGuard setup in this directory is for. Cost is not a reason to avoid it: the
free Personal plan covers 6 users and unlimited personal devices.

Tailscale managed its own interface outside NetworkManager, so the waybar module
never showed it — that was expected, not a bug. If you reinstall it, the two
coexist fine and do different jobs.
