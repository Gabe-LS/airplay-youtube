# airplay-youtube

A macOS automation that grabs a YouTube URL from your browser and plays it in [mpv](https://mpv.io) with hardware-accelerated decoding, optional AirPlay audio routing via [Airfoil](https://rogueamoeba.com/airfoil/mac/), and automatic volume adjustment for quiet videos.

I built this to watch YouTube on my Mac while routing audio to a Sonos speaker over AirPlay. It works with any AirPlay receiver — Sonos, HomePod, Apple TV, or anything else Airfoil can see.

## What it does

1. **Finds your YouTube tab** across Brave, Chrome, and Safari — auto-selects the active tab, or shows a picker if there are multiple
2. **Pauses the browser video** to avoid double audio
3. **Preserves the timestamp** (`t=` parameter) so playback resumes where you left off
4. **Launches mpv** in iTerm or Terminal.app with a minimal config (no OSC, custom keybindings, capped resolution)
5. **Routes audio** to an AirPlay speaker via Airfoil *(optional)*
6. **Switches WiFi** to a specific network before playback *(optional)*
7. **Adjusts volume for quiet videos** — measures LUFS in the background and applies a linear gain offset to bring quiet videos up to −14 LUFS (YouTube's target). No compression or dynamic processing — just a volume change, clamped by a true-peak ceiling. Never attenuates.

## Requirements

- macOS (tested on Sonoma / Sequoia)
- [Homebrew](https://brew.sh) (Apple Silicon or Intel — auto-detected)
- At least one of: [Brave](https://brave.com), Chrome, or Safari
- [Airfoil](https://rogueamoeba.com/airfoil/mac/) *(only if you want AirPlay speaker routing)*
- [iTerm2](https://iterm2.com) *(optional — falls back to Terminal.app)*

### Browser setup

JavaScript from Apple Events must be enabled for the script to pause the browser video and detect tabs:

- **Brave / Chrome:** View → Developer → Allow JavaScript from Apple Events
- **Safari:** Develop → Allow JavaScript from Apple Events

The script still works without this — it just can't pause the video in the browser.

### Homebrew dependencies

```bash
brew install mpv yt-dlp ffmpeg python3
```

The script checks for these at startup and tells you what's missing.

## Setup

1. Clone or download `airplay-youtube.applescript`
2. Open it and edit the **Configuration** block at the top:

| Variable | Default | Description |
|---|---|---|
| `requiredNetwork` | `""` | WiFi network to switch to before playback. Leave empty to skip. |
| `speakerName` | `""` | Airfoil speaker name (e.g. `"Kitchen"`). Leave empty to play locally. |
| `speakerVolume` | `0.2` | AirPlay speaker volume (0.0–1.0) |
| `audioDelay` | `"-2"` | Seconds to shift audio earlier. Only applied when Airfoil is active. Tune to your speaker's latency. |
| `maxVideoHeight` | `1080` | Cap video resolution (e.g. `720`, `1080`, `1440`) |
| `targetLUFS` | `"-14"` | Target loudness. Videos quieter than this get a volume boost. `-14` is YouTube's standard. |
| `peakCeiling` | `"-1"` | Max true peak (dBTP) after boost. Caps the gain to prevent clipping. |

3. Run it from Script Editor, `osascript`, Shortcuts, or any AppleScript runner

### WiFi password

If you set `requiredNetwork`, the script will prompt for the password on first use and store it in your **login keychain**. Subsequent runs read it silently. If the connection fails, the stored password is cleared so you get prompted again.

### Using with Sonos

Set `speakerName` to the name of your Sonos speaker as it appears in Airfoil (e.g. `"Kitchen"`, `"Living Room"`). Airfoil routes audio to Sonos over AirPlay — no Sonos app or API involved. You may need to adjust `audioDelay` to compensate for your speaker's AirPlay latency (start with `"-2"` and tune from there).

## Keybindings

mpv launches with a minimal input config:

| Key | Action |
|---|---|
| Space | Play / Pause |
| ↑ / ↓ | Volume ±2 |
| ← / → | Seek ±5s |
| F | Toggle fullscreen |
| Esc | Exit fullscreen |
| Q | Quit |
| M | Toggle mute |
| O | Show progress |
| Double-click | Toggle fullscreen |

## How volume adjustment works

A background Python script downloads the audio-only stream (piped through ffmpeg, nothing saved to disk) and measures integrated LUFS and true peak via ffmpeg's `ebur128` filter. It then calculates a single linear gain offset — the difference between the measured loudness and the target (−14 LUFS). This is applied by adjusting mpv's volume slider, not by processing the audio signal. No compression, limiting, or dynamic range manipulation of any kind.

- **Boost only** — if the video is already at or above −14 LUFS, nothing happens
- **Peak-clamped** — gain is limited so true peaks never exceed the ceiling (default −1 dBTP)
- **Smooth ramp** — volume adjusts gradually over several seconds via mpv's IPC socket
- **OSD overlay** — a small status indicator shows measurement progress and final values

Logs are written to `/tmp/mpv-loudness.log`.

## Troubleshooting

- **mpv exits immediately** — check the terminal tab for error output. Usually a yt-dlp or format issue.
- **No audio on speaker** — verify the speaker name matches exactly what Airfoil shows. The script warns if the speaker isn't found or fails to connect.
- **Volume adjustment fails** — check `/tmp/mpv-loudness.log`. Common causes: network timeout, geo-blocked video, or ffmpeg issue.
- **"Allow JavaScript" prompt** — enable it in your browser's developer menu (see Browser setup above). The script can find tabs without it, but can't pause the browser video.

## License

MIT
