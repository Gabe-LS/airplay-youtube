# AirPlay YouTube

Play a YouTube video from your browser in a dedicated player, with the option to send audio to a wireless speaker (Sonos, HomePod, Apple TV, or any AirPlay receiver).

I built this to watch YouTube on my Mac while routing audio to a Sonos speaker in another room. It also automatically turns up the volume on quiet videos so you don't have to.

---

## What it does

1. Finds your YouTube tab in Brave, Chrome, or Safari
2. Pauses the browser video so you don't get double audio
3. Opens the video in [mpv](https://mpv.io) — a fast, lightweight video player
4. If you were partway through the video, it picks up where you left off
5. Optionally sends audio to a wireless speaker via [Airfoil](https://rogueamoeba.com/airfoil/mac/)
6. Optionally switches your WiFi network before playing
7. Automatically boosts the volume on quiet videos (no audio processing — just turns up the volume)

---

## Before you start

You need a Mac running macOS Sonoma or later, and [Homebrew](https://brew.sh) — a tool that installs command-line software on macOS.

**Check if Homebrew is installed:** open the Terminal app (press `Command + Space`, type `Terminal`, press Enter), then type:

```
brew --version
```

If you see a version number, you're good. If you see "command not found", install Homebrew by following the instructions at [brew.sh](https://brew.sh).

---

## Step 1 — Install dependencies

Open Terminal and run:

```
brew install mpv yt-dlp ffmpeg python3
```

This installs the video player and the tools it needs. You only need to do this once.

---

## Step 2 — Enable JavaScript in your browser

This lets the script find your YouTube tabs and pause the browser video. Pick the browser you use:

- **Brave or Chrome:** go to View → Developer → Allow JavaScript from Apple Events
- **Safari:** go to Develop → Allow JavaScript from Apple Events

> **Safari note:** if you don't see the Develop menu, go to Safari → Settings → Advanced and check "Show features for web developers".

The script still works without this step — it just won't be able to pause the video in the browser automatically.

---

## Step 3 — Download the script

1. Click the green **Code** button at the top of this page
2. Click **Download ZIP**
3. Unzip the file — you'll get a folder containing `AirPlay YouTube.applescript`

Or if you use git:

```
git clone https://github.com/Gabe-LS/airplay-youtube.git
```

---

## Step 4 — Configure (optional)

The defaults work out of the box — you only need to change things if you want to use a wireless speaker or auto-switch WiFi.

To customize, create a file called `airplay_youtube.config.json` in the same folder as the script. Only include the settings you want to change — everything else uses the defaults. An example file (`airplay_youtube.config.example.json`) is included in the repo.

### Play audio on a wireless speaker

If you have [Airfoil](https://rogueamoeba.com/airfoil/mac/) and want to route audio to a speaker, create `airplay_youtube.config.json` with:

```json
{
  "speakerName": "Kitchen",
  "dayVolume": 0.2,
  "nightVolume": 0.15,
  "dayStart": "07:00",
  "nightStart": "23:30"
}
```

This works with any AirPlay receiver — Sonos, HomePod, Apple TV, etc. Set both volumes to the same value if you don't want time-based changes. You may need to adjust `audioDelay` to compensate for the slight delay that AirPlay adds — start with `"-2"` and tune from there.

### Auto-switch WiFi

If your speaker is on a different WiFi network:

```json
{
  "speakerName": "Kitchen",
  "requiredNetwork": "MyNetwork_5G"
}
```

The first time, the script will ask for the WiFi password and save it to your keychain. The password is only saved after the connection is verified — if the network name is wrong, nothing gets stored.

### All settings

| Setting | Default | What it does |
|---|---|---|
| `requiredNetwork` | `""` | WiFi network to connect to before playing. Leave empty to skip. |
| `speakerName` | `""` | Airfoil speaker name. Leave empty to play audio on your Mac. |
| `audioDelay` | `"-2"` | Shift audio earlier to compensate for AirPlay lag. Only used with a speaker. |
| `dayVolume` | `0.2` | Speaker volume during the day, from 0.0 (silent) to 1.0 (full). |
| `nightVolume` | `0.15` | Speaker volume at night. |
| `dayStart` | `"07:00"` | When daytime volume kicks in (24h format). |
| `nightStart` | `"23:30"` | When nighttime volume kicks in (24h format). |
| `maxVideoHeight` | `1080` | Maximum video quality. Use `720` for slower connections. |
| `cacheSize` | `"50M"` | How much video to buffer in memory. |
| `cachePauseWait` | `"5"` | Seconds to re-buffer after a network stall before resuming. |
| `targetLUFS` | `"-14"` | How loud quiet videos should be boosted to. `-14` is YouTube's standard. |
| `peakCeiling` | `"-1"` | Safety limit to prevent distortion when boosting volume. |

---

## Step 5 — Run

1. Open a YouTube video in Brave, Chrome, or Safari
2. Open `AirPlay YouTube.applescript` in Script Editor (double-click it)
3. Click the ▶ Run button

The video will open in mpv. If you have multiple YouTube tabs open, the script will ask you to pick one.

### Other ways to run

- **From Terminal:** `osascript "AirPlay YouTube.applescript"`
- **From Shortcuts:** add a "Run AppleScript" action and paste the script
- **From the menu bar:** save as an application in Script Editor (File → Export → File Format: Application)

---

## Keyboard controls

Once the video is playing in mpv:

| Key | What it does |
|---|---|
| Space | Play / Pause |
| ↑ / ↓ | Volume up / down |
| ← / → | Skip 5 seconds back / forward |
| Shift + ← / → | Skip 60 seconds back / forward |
| F | Fullscreen |
| Esc | Exit fullscreen |
| Q | Quit |
| M | Mute / Unmute |
| O | Show playback progress |
| Double-click | Fullscreen |

---

## Something not working?

- **mpv closes right away** — look at the terminal window behind it for an error message. This is usually a network or video format issue.
- **WiFi won't connect** — the error will show both the expected and actual network name, so you can spot any typo in the config.
- **No audio on speaker** — make sure `speakerName` matches exactly what Airfoil shows. The script will warn you if the speaker isn't found.
- **Video is still quiet** — check `/tmp/mpv-loudness.log` for details. Common causes: slow connection, geo-blocked video, or a problem with ffmpeg.
- **Browser video doesn't pause** — enable JavaScript from Apple Events in your browser (see Step 2).

---

## Features

- Works with Brave, Chrome, and Safari
- Picks up where the video left off (preserves timestamps)
- Uses iTerm if available, falls back to Terminal.app
- Boosts quiet videos to a consistent volume (linear gain only — no compression or audio processing)
- Homebrew path auto-detected (works on both Apple Silicon and Intel Macs)
- WiFi password stored securely in the macOS keychain
- Day/night speaker volume schedule — plays quieter at night automatically

<details>
<summary>How volume adjustment works (technical)</summary>

A background Python script downloads the audio-only stream (piped through ffmpeg, nothing saved to disk) and measures integrated LUFS and true peak via ffmpeg's `ebur128` filter. It calculates a single linear gain offset — the difference between the measured loudness and the target (−14 LUFS). This is applied by adjusting mpv's volume slider, not by processing the audio signal. No compression, limiting, or dynamic range manipulation of any kind.

- **Boost only** — if the video is already at or above −14 LUFS, nothing happens
- **Peak-clamped** — gain is limited so true peaks never exceed the ceiling (default −1 dBTP)
- **Smooth ramp** — volume adjusts gradually over several seconds via mpv's IPC socket
- **OSD overlay** — a small status indicator shows measurement progress and results

Logs are written to `/tmp/mpv-loudness.log`.

</details>

---

## License

MIT License — Copyright (c) 2025 Gabriele Lo Surdo
