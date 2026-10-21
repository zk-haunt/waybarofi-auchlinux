# Manual upkeep

The installer automates everything it safely can. These four jobs stay manual
on purpose — each one needs you to read something or make a call — so here is
how to do them.

| Task | When | Takes |
|---|---|---|
| [1. Firmware updates](#1-firmware-updates-fwupd) | every month or two | ~2 min + a reboot |
| [2. Arch news](#2-arch-news-informant) | when an upgrade stops with "unread news" | ~1 min |
| [3. Security audit](#3-security-audit-lynis) | after hardening changes, or every few months | ~3 min |
| [4. AppArmor](#4-apparmor-optional) | once, if you want it | ~10 min + 2 reboots, then a few days of normal use |

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

---

## 4. AppArmor (optional)

**What it is:** rules for each program about what it may touch. Normally any
program you run can read everything you can — SSH keys, the password database,
browser logins. With a rule like "Telegram may read its own folder and
Downloads", a hacked Telegram is stuck inside that.

**What is already automatic:** nothing. The kernel has AppArmor built in but
switched off, and the installer leaves it that way.

**Why it stays manual:** switching it on means editing the boot entry, and a
rule that is too strict breaks a program in confusing ways — a file silently
won't open. So it goes on in log-only mode first, and you decide later which
rules may actually block.

```bash
# 1. Upgrade, and install the tools plus the rules that ship with them.
#    Don't enable the service yet — that's step 4.
sudo pacman -Syu apparmor

# 2. Make a second boot entry with AppArmor switched on. Your normal entry is
#    left alone: if anything goes wrong, reboot and pick that one. (Editing at
#    the boot menu is turned off.) Stable kernel? Use arch.conf, not arch-zen.conf.
#    The new entry is NOT the default: /boot/loader/loader.conf still says
#    `default arch-zen.conf`, so it only runs when picked by hand until step 4
#    switches the default over.
sudo cp /boot/loader/entries/arch-zen.conf /boot/loader/entries/arch-zen-apparmor.conf
#    Add apparmor to the security-module list the kernel uses today, just
#    BEFORE bpf. Writing only lsm=apparmor would switch the others off, and
#    with bpf ahead of it the kernel's audit logging breaks: audit-rules.service
#    fails and "error in audit_log_subj_ctx" floods the log.
LSM="$(sed 's/,apparmor//; s/,bpf/,apparmor,bpf/; /apparmor/!s/$/,apparmor/' /sys/kernel/security/lsm)"
sudo sed -i -e 's/^title.*/title   Arch Linux (AppArmor test)/' \
            -e "/^options/ s/\$/ lsm=$LSM/" \
            /boot/loader/entries/arch-zen-apparmor.conf
sudo cat /boot/loader/entries/arch-zen-apparmor.conf   # as before, plus lsm=…,apparmor,bpf at the end

# 3. Reboot and pick "AppArmor test" in the menu — after 5 seconds it boots
#    your normal entry instead. AppArmor is now on with no rules loaded, so
#    nothing behaves differently yet.
aa-enabled                                       # Yes
systemctl --failed                               # lists nothing
sudo aa-status                     # "Failed to get profiles: 2" = no rules loaded yet

# 4. Load the shipped rules in log-only mode: apparmor.mode=complain makes
#    every rule log what it would block, instead of blocking it.
sudo sed -i '/^options/ s/$/ apparmor.mode=complain/' /boot/loader/entries/arch-zen-apparmor.conf
#    Now REBOOT into "AppArmor test" again — the switch only takes effect at
#    boot. Then this enables the service only if it did (safe to paste whole):
if [ "$(sudo cat /sys/module/apparmor/parameters/mode)" = complain ]; then
    sudo systemctl enable --now apparmor
else
    echo "Still in enforce mode: reboot into AppArmor test first. Service not enabled."
fi
#    Then make "AppArmor test" the default boot entry. Without this every
#    normal boot runs with AppArmor off, and step 5's log only grows on the
#    boots you picked by hand. The old entry stays in the menu (5 s) as the
#    fallback. A `d` pressed in the boot menu, or `bootctl set-default`, sets a
#    firmware variable that overrides this line — `bootctl list` shows which
#    entry really is "(default)".
sudo sed -i 's/^default .*/default arch-zen-apparmor.conf/' /boot/loader/loader.conf
sudo bootctl list --no-pager | grep -E '^ *(title|id):'

# 5. Use the laptop normally for a few days, then see what would have been
#    blocked. auditd is running, so AppArmor logs to the audit log — not to
#    journalctl.
sudo grep 'apparmor="ALLOWED"' /var/log/audit/audit.log | less

# 6. Make the rules block for real — only once step 5's log looks right.
#    For each rule that shows up there, either let aa-logprof add what it was
#    missing (it asks about each line), or keep just that one rule log-only:
sudo aa-logprof
sudo aa-complain /etc/apparmor.d/<rule-file>     # one file — never /etc/apparmor.d/*
#    One missing line is simpler by hand, in the rule's local file — package
#    updates leave it alone (2026-10-16: zgrep run with sudo lacked this one):
echo 'capability dac_read_search,' | sudo tee -a /etc/apparmor.d/local/zgrep
sudo apparmor_parser -r /etc/apparmor.d/zgrep
#    Then switch the system-wide log-only mode off, now and for later boots.
#    Rules you set log-only above stay log-only.
sudo sed -i 's/ apparmor.mode=complain//' /boot/loader/entries/arch-zen-apparmor.conf
printf enforce | sudo tee /sys/module/apparmor/parameters/mode
```

Good to know:
- **Don't run `aa-complain /etc/apparmor.d/*`**, a common tip. About half the
  shipped rules — brave, Discord, steam and others — are marked `unconfined`
  and block nothing; `aa-complain` rewrites them into real rules that allow
  almost nothing. That floods the log now, and breaks those apps if you ever
  enforce them. The switch in step 4 changes no rule file.
- **Out of the box it protects very little.** The `unconfined` rules block
  nothing, and most of the rest are for server software. The value is in rules
  for the programs you care about — `sudo aa-logprof` turns step 5's log into
  rule changes.
- **Enabled the service while `mode` said enforce?** Then the rules are
  blocking right now. `printf complain | sudo tee /sys/module/apparmor/parameters/mode`
  switches every rule to log-only at once, without a reboot (`printf`, not
  `echo`: the file rejects the trailing newline with "Invalid argument"); the
  `apparmor.mode=complain` on the boot line keeps it that way from the next
  boot on.
- **Step 6 turns on every shipped rule at once**, including the one for the
  helper that checks your lock-screen password. That's why it waits for a
  clean log: a rule missing something would otherwise break that program.
- **Rules for your own apps** (Telegram, Discord…): none ship — Discord's is
  `unconfined`. `sudo aa-genprof /usr/bin/Telegram` builds one: it watches
  while you use the app, then asks about each thing the app did. Expect it to
  take a session of its own.
- `sudo aa-status` lists what is loaded. It can still show rules under
  "enforce mode": that's each rule's own setting, and the `mode` file from
  step 4 overrides it. `ps -eo label,pid,comm` shows the rule each running
  program is under (`unconfined` = none), and
  `sudo tail -f /var/log/audit/audit.log | grep --line-buffered apparmor`
  shows AppArmor's messages live.
- Your normal entry boots exactly as before, even with the service enabled —
  the service only runs when AppArmor is on. To remove everything:
  `sudo systemctl disable apparmor`, set `default arch-zen.conf` back in
  `/boot/loader/loader.conf` (it points at the AppArmor entry since step 4 —
  a default naming a deleted entry leaves the menu guessing), delete
  `/boot/loader/entries/arch-zen-apparmor.conf`, then `sudo pacman -Rns apparmor`.
