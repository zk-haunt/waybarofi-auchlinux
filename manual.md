# Manual upkeep

The installer automates everything it safely can. These three jobs stay manual
on purpose — each one needs you to read something or make a call — so here is
how to do them.

| Task | When | Takes |
|---|---|---|
| [1. Firmware updates](#1-firmware-updates-fwupd) | every month or two | ~2 min + a reboot |
| [2. Arch news](#2-arch-news-informant) | when an upgrade stops with "unread news" | ~1 min |
| [3. Security audit](#3-security-audit-lynis) | after hardening changes, or every few months | ~3 min |

---

## 1. Firmware updates (fwupd)

**What it is:** updates for the firmware inside your hardware — BIOS/UEFI, SSD,
and the Secure Boot revocation list — published by vendors on LVFS.

**What is already automatic:** a daily timer downloads LVFS's catalogue
(set up by `scripts/harden-system.sh`). It never installs anything.

**Why it stays manual:** flashing firmware needs the charger plugged in and a
reboot, and losing power mid-flash can brick the device. You pick the moment.

```bash
# 1. See what's available for this machine. Read-only — changes nothing.
#    "No updates available" is the normal answer.
fwupdmgr get-updates

# 2. PLUG IN THE CHARGER. Updates refuse to start on battery anyway.

# 3. Install what step 1 listed. It asks before each update. Most need a
#    reboot, and the actual flash happens during that reboot — don't power
#    off while it runs, even if the screen looks stuck.
fwupdmgr update
```

Good to know:
- If step 1 says the metadata is out of date, run `fwupdmgr refresh` first.
- `fwupdmgr get-history` shows what was installed before and whether it worked.
- Not every vendor publishes on LVFS. If your BIOS never shows up here, check
  the manufacturer's support page for that model instead.
- Updates touch firmware only — never your files, kernel or bootloader.

---

## 2. Arch news (informant)

**What it is:** Arch sometimes ships an update that breaks things unless you do
a step by hand first, and announces it on the news page. `informant` adds a
pacman hook that **stops every upgrade** until you've read the news.

**What is already automatic:** the hook (installed by `install-packages.sh`).
`Super + U` also shows unread news before it upgrades.

**Why it stays manual:** the whole point is that *you* read it.

When `sudo pacman -Syu` stops with *"There are N unread news items"*:

```bash
# 1. Show each unread item in full and mark it read.
sudo informant read

# 2. If an item applies to you, do what it says — it gives the exact
#    commands. Does it apply? If it names a package, check whether you have it:
pacman -Q <package-name>        # "was not found" = not installed = skip that item

# 3. Upgrade again; it goes through now.
sudo pacman -Syu
```

Good to know:
- `informant list` shows recent titles without marking anything read. Without
  sudo it prints a harmless "Unable to read cache information" warning first.
- **Do not** join the `informant` group to avoid typing sudo. Its read-state
  file is loaded as root before every upgrade and can carry code, so group
  membership would let anything running as you become root. Details in
  `scripts/harden-system.sh`.

---

## 3. Security audit (Lynis)

**What it is:** a read-only audit of the whole system that prints suggestions
and a score (the "hardening index", 0–100).

**What is already automatic:** a weekly scan for vulnerable packages
(`malware-scan.timer`) — Lynis is the broader, occasional check on top of it.

**Why it stays manual:** it's a check, not a setting. The output needs a human
to decide which suggestions fit a desktop — many are written for servers.

```bash
# 1. Run the full audit. About 2–3 minutes; changes nothing.
#    The score is near the end: "Hardening index : NN".
sudo lynis audit system

# 2. Later, re-read just the score, warnings and suggestions from the last run.
sudo grep -E '^(hardening_index|warning|suggestion)' /var/log/lynis-report.dat

# 3. Explain one suggestion in detail, using the ID in brackets, e.g. [KRNL-6000].
sudo lynis show details KRNL-6000
```

Good to know:
- The score is a guide, not a goal. Suggestions already considered and turned
  down — with the reason for each — are listed at the bottom of
  `scripts/harden-system.sh`, so they don't need deciding again.
- "Vulnerable packages found" usually means advisories with no fix released
  yet. `./scripts/malware-scanner.sh` separates those from ones you can fix.
- If you do act on a suggestion, put the change in `config/etc/` and
  `scripts/harden-system.sh`, so the next install gets it too.
