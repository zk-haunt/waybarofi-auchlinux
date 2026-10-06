#!/usr/bin/env bash
# =============================================================================
#  Encrypted DNS for AuchLinux — systemd-resolved + DNS-over-TLS + DNSSEC
#  Replaces plaintext DNS (e.g. an institutional 10.x/172.16.x resolver) with
#  authenticated, encrypted lookups.
#
#  Note how DNSOverTLS=yes (strict) does the real work: a DHCP-pushed resolver
#  that refuses port 853 simply cannot be used, so queries fall through to the
#  Quad9/Cloudflare DoT servers configured below instead of silently downgrading
#  to plaintext. resolvectl will still SHOW the pushed server as the per-link
#  "Current DNS Server" — that is the configured server, not the one answering.
#
#  DNS only. The firewall used to live here as "step 7" (nftables); it is now
#  ufw, set up separately — see plansecurity.md P1. Tailscale handling was also
#  removed, as tailscale is no longer installed on this machine.
#
#  Usage:
#     sudo ./scripts/harden-dns.sh            # apply
#     sudo ./scripts/harden-dns.sh --revert   # undo
#     sudo ./scripts/harden-dns.sh --status   # show resolver state
#
#  Safe to re-run (idempotent). Run after a fresh install (post-install step).
# =============================================================================
set -euo pipefail

RESOLVED_CONF=/etc/systemd/resolved.conf.d/dns-over-tls.conf
NM_CONF=/etc/NetworkManager/conf.d/dns.conf

c(){ printf '\033[0;36m[dns]\033[0m %s\n' "$*"; }
ok(){ printf '\033[0;32m[ok]\033[0m  %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m  %s\n' "$*"; }

# Re-exec as root if needed.
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

case "${1:-apply}" in
  --status)
    resolvectl status 2>/dev/null | grep -E "Current DNS|DNS Servers|DNSOverTLS|DNSSEC|Protocols" || true
    echo "resolv.conf -> $(readlink -f /etc/resolv.conf)"
    # `systemctl is-enabled` prints "not-found" on stdout AND exits non-zero, so
    # a bare `|| echo ...` yields both strings. Capture, then decide.
    fw_unit="$(systemctl is-enabled ufw 2>/dev/null || true)"
    [[ -n "$fw_unit" && "$fw_unit" != "not-found" ]] || fw_unit="not installed"
    fw_state="$(ufw status 2>/dev/null | head -1 || true)"
    [[ -n "$fw_state" ]] || fw_state="status unavailable"
    echo "firewall    -> ufw unit: $fw_unit | $fw_state"
    exit 0 ;;
  --revert)
    c "Reverting to NetworkManager-managed DNS…"
    rm -f "$RESOLVED_CONF" "$NM_CONF"
    systemctl disable --now systemd-resolved 2>/dev/null || true
    # let NetworkManager own resolv.conf again
    rm -f /etc/resolv.conf
    systemctl restart NetworkManager
    ok "Reverted. (Re-run without --revert to re-apply.)"
    # The firewall is separate from this script now, so --revert cannot widen
    # your exposure the way it could when the two were bundled.
    warn "Firewall untouched (ufw is managed separately): sudo ufw disable"
    exit 0 ;;
esac

# 1. DoT + DNSSEC resolver config (multiple DoT-capable providers + fallback)
c "Writing $RESOLVED_CONF …"
install -d /etc/systemd/resolved.conf.d
cat > "$RESOLVED_CONF" <<'EOF'
[Resolve]
# Preference order: Quad9 -> Cloudflare -> NextDNS. No Google.
# NextDNS here is the generic (unfiltered) anycast endpoint. For YOUR filtered
# NextDNS profile, sign up (free) and replace the hostname with your config id:
#   45.90.28.0#<id>.dns.nextdns.io  45.90.30.0#<id>.dns.nextdns.io
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 45.90.28.0#dns.nextdns.io 45.90.30.0#dns.nextdns.io
# Empty FallbackDNS = disable systemd's built-in fallback (which includes Google).
FallbackDNS=
DNSOverTLS=yes
DNSSEC=allow-downgrade
Cache=yes
EOF

# 2. enable + (re)start the resolver
#    NB: use restart, not `enable --now` — if resolved is already running (e.g. a
#    re-run after editing the config), `--now` won't reload it and you'd keep the
#    OLD servers. restart forces it to read the new config.
c "Enabling + restarting systemd-resolved…"
systemctl enable systemd-resolved
systemctl restart systemd-resolved
resolvectl flush-caches 2>/dev/null || true

# 3. point resolv.conf at the resolved stub, so every resolver client goes
#    through resolved (and therefore through DoT) rather than reading a
#    DHCP-supplied nameserver straight out of the file
c "Linking /etc/resolv.conf -> resolved stub…"
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 4. hand DNS resolution to resolved in NetworkManager
c "Configuring NetworkManager dns=systemd-resolved…"
install -d /etc/NetworkManager/conf.d
cat > "$NM_CONF" <<'EOF'
[main]
dns=systemd-resolved
EOF
systemctl restart NetworkManager

# 5. verify — retry, because the NetworkManager restart takes a few seconds to
#    settle (a single immediate query gives false "failed" warnings).
c "Resolver status:"
resolvectl status 2>/dev/null | grep -E "Current DNS|DNS Servers|DNSOverTLS|DNSSEC" || true
ok_query=0
for _ in 1 2 3 4 5 6; do
  if resolvectl query archlinux.org >/dev/null 2>&1; then ok_query=1; break; fi
  sleep 2
done
if [ "$ok_query" = 1 ]; then
  ok "Encrypted DNS active (DoT + DNSSEC). Test query succeeded."
else
  warn "Test query still failing after ~12s. Likely a captive portal (sign in first) or a"
  warn "network blocking port 853. Temp fix: DNSOverTLS=opportunistic in $RESOLVED_CONF, or run with --revert."
fi
echo
c "Captive-portal tip: strict DoT can stall portal sign-in pages. If a café/hotel"
c "Wi-Fi won't load, run '--revert' for that session (or switch to opportunistic)."
