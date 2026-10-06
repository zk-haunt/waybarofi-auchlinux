# VTube — face-tracked avatar as a webcam

Puppet a 2D avatar with your face and feed it into Meet, Discord, OBS or
anything else that accepts a camera. Runs natively on Linux — no Proton.

Optional: nothing else in the repo depends on it.

## How it works

```
webcam (/dev/video0)
  → OpenSeeFace tracker          reads your face, sends data over UDP :11573
  → Inochi Session               renders your avatar, driven by that data
  → wf-recorder                  captures that window
  → /dev/video10                 a virtual camera other apps can select
```

The last step is the trick: apps can't read a *window*, only a camera device.
`v4l2loopback` provides a fake camera, and `wf-recorder` continuously pipes the
avatar window into it.

**Why this stack:** VTube Studio under Proton has broken webcam passthrough.
Inochi Session is a native renderer that speaks OpenSeeFace tracking directly.

## Prerequisites

| Need | Status on this machine |
|---|---|
| A real webcam | ✅ `/dev/video0` present |
| `wf-recorder` | ✅ installed |
| `v4l2loopback` → `/dev/video10` | ✅ installed (`v4l2loopback-dkms`, `/dev/video10` present) |
| An avatar model (`.inp` file) | you must supply this |

**`v4l2loopback` is required and is already installed.** Without it there'd be
no `/dev/video10`, so the avatar can't be exposed as a camera. It comes from
the main bootstrap:

```bash
sudo pacman -S --needed v4l2loopback-dkms linux-zen-headers
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="Phone Camera" exclusive_caps=1
```

`install-packages.sh` also writes a modprobe config so the device is created
automatically at every boot.

> The virtual camera is labelled **"Phone Camera"** because it's shared with
> the phone-as-webcam scripts. Only one of them can use it at a time.

## Setup

```bash
./scripts/vtube/vtube.sh setup
```

Installs Inochi Session + Creator from the AUR, and OpenSeeFace — falling back
to a local Python venv if the AUR package fails to build. Then checks the
virtual camera exists.

**You also need an avatar model.** Inochi Session renders `.inp` files; it
doesn't ship one. Either grab an example from [inochi2d.com](https://inochi2d.com)
or build your own in `inochi-creator` (installed by setup).

## Daily use

### 1. Start tracking and the avatar

```bash
./scripts/vtube/vtube.sh run
```

Starts the face tracker on your webcam and opens Inochi Session.

**One-time inside Inochi Session:**
1. Load your model (`.inp`).
2. Settings → Tracking → add an **OpenSeeFace** source on port **11573**.

Your avatar should now follow your face. Position and size the window to frame
it how you want it to appear on camera — the next step captures exactly that
window region.

### 2. Publish it as a camera

```bash
./scripts/vtube/vtube.sh cam
```

Finds the Session window automatically, then mirrors it into `/dev/video10`.
**This runs in the foreground — leave it running and Ctrl+C to stop.**

### 3. Select it in your app

Pick **"Phone Camera"** as the camera device in Meet, Discord, OBS, etc.

### 4. Stop everything

```bash
./scripts/vtube/vtube.sh stop
```

Kills the capture, the tracker and Inochi Session.

## Tuning

Environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `VTUBE_CAM` | `/dev/video0` | which real webcam to track from |
| `VTUBE_LOOPDEV` | `/dev/video10` | which virtual camera to publish to |

```bash
VTUBE_CAM=/dev/video2 ./scripts/vtube/vtube.sh run
```

**On a slow CPU**, the tracker's quality setting is the thing to lower — it
defaults to the highest (`--model 3`). Edit the `run()` function and drop it to
`--model 1`. Face tracking is the expensive part of this pipeline.

## Troubleshooting

**"No Inochi Session window found"** — `cam` looks for a window whose class
contains `inochi-session`. Run `run` first and let the window actually open.

**Avatar doesn't move** — the tracking source isn't connected. Check Settings →
Tracking in Session lists OpenSeeFace on port 11573, and that the tracker is
alive: `pgrep -f facetracker`.

**Camera missing in other apps** — either `cam` isn't running (it must stay in
the foreground) or `/dev/video10` doesn't exist. Check with
`ls -l /dev/video10` and `v4l2-ctl --list-devices`.

**Some apps only see the camera if it existed when they started** — restart the
app after starting `cam`.

**"Phone Camera" already in use** — the phone-as-webcam scripts share this
device. Stop those first.
