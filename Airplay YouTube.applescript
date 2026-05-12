-- =============================================================================
-- AirPlay YouTube
--
-- Plays a YouTube video from Brave, Chrome, or Safari in mpv with optional
-- AirPlay audio routing via Airfoil and automatic volume adjustment for
-- quiet videos.
--
-- Features:
--   - Grabs the YouTube URL from Brave, Chrome, or Safari
--   - Auto-selects: active tab > only YouTube tab > picker for multiple tabs
--   - Preserves YouTube timestamp (t= parameter) for seek-to-position
--   - Plays in mpv via iTerm (falls back to Terminal.app if iTerm is absent)
--   - Hardware-accelerated decoding, capped resolution, minimal UI
--   - Optional: switches WiFi network before playback
--   - Optional: routes audio to an AirPlay speaker via Airfoil
--     (works with any AirPlay receiver — Sonos, HomePod, Apple TV, etc.)
--   - Background loudness measurement adjusts volume for quiet videos
--     (linear gain only — no compression or dynamic processing)
--
-- Requirements:
--   - macOS with Homebrew (Apple Silicon or Intel — auto-detected)
--   - brew install mpv yt-dlp ffmpeg python3
--   - Brave, Chrome, or Safari
--   - For Brave/Chrome: View → Developer → Allow JavaScript from Apple Events
--   - For Safari: Develop → Allow JavaScript from Apple Events
--   - Airfoil (optional, only needed if speakerName is set)
--
-- Usage:
--   Open a YouTube video in any supported browser, then run this script
--   via Script Editor, osascript, Shortcuts, or any AppleScript runner.
--
-- License: MIT
-- =============================================================================

-- =============================================================================
-- CONFIGURATION (defaults — override any of these in airplay_youtube.config.json)
-- =============================================================================
set mpvTabTitle to "MPV Player" -- Tab identifier for terminal session

-- WiFi — set to "" to skip network switching
set requiredNetwork to "" -- e.g. "MyNetwork_5G"

-- Airfoil — set speakerName to "" to skip audio routing (plays locally)
-- Works with any AirPlay receiver: Sonos, HomePod, Apple TV, etc.
set speakerName to "" -- e.g. "Kitchen", "Living Room"
set audioDelay to "-2" -- Audio delay in seconds (negative = audio plays earlier, compensating for AirPlay speaker latency)

-- Speaker volume (0.0 to 1.0) — time-based day/night levels
-- Day volume applies from dayStart to nightStart (24h format), night volume for the rest.
-- Set both to the same value for a single fixed volume.
set dayVolume to 0.2
set nightVolume to 0.15
set dayStart to "07:00"
set nightStart to "23:30"

-- Video
set maxVideoHeight to 1080 -- Maximum video resolution

-- Cache
set cacheSize to "50M" -- Demuxer max bytes
set cacheReadahead to "10" -- Demuxer readahead seconds
set cachePauseWait to "5" -- Seconds to wait when cache is empty

-- Volume adjustment for quiet videos (linear gain only, no compression, boost only, never attenuates)
set targetLUFS to "-14" -- Target integrated loudness (LUFS), YouTube default
set peakCeiling to "-1" -- Maximum true peak after gain (dBTP), prevents distortion

-- =============================================================================
-- LOAD CONFIG FILE (if present next to the script)
-- =============================================================================

-- Looks for airplay_youtube.config.json in the same folder as this script.
-- Any keys in the JSON override the defaults above. Unknown keys are ignored.
-- If the file doesn't exist, the defaults are used as-is.
--
-- Path detection tries multiple methods:
--   1. path to me — works for osascript and .app bundles
--   2. Script Editor document path — works when running from Script Editor
try
	set configPath to ""
	
	-- Method 1: path to me (works for osascript and .app bundles)
	try
		set myPath to POSIX path of (path to me)
		-- Skip if this points to an .app bundle (Script Editor, Shortcuts, etc.)
		if myPath does not end with ".app/" and myPath does not contain ".app/Contents" then
			set scriptDir to do shell script "dirname " & quoted form of myPath
			set testPath to scriptDir & "/airplay_youtube.config.json"
			if (do shell script "test -f " & quoted form of testPath & " && echo yes || echo no") is "yes" then
				set configPath to testPath
			end if
		end if
	end try
	
	-- Method 2: Script Editor document path
	if configPath is "" then
		try
			tell application "System Events"
				if exists process "Script Editor" then
					tell application "Script Editor"
						set docPath to path of front document
					end tell
					set scriptDir to do shell script "dirname " & quoted form of docPath
					set testPath to scriptDir & "/airplay_youtube.config.json"
					if (do shell script "test -f " & quoted form of testPath & " && echo yes || echo no") is "yes" then
						set configPath to testPath
					end if
				end if
			end tell
		end try
	end if
	
	if configPath is not "" then
		-- Parse JSON with python3 and output key=value pairs
		set configPairs to do shell script "python3 -c \"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for k, v in data.items():
    if isinstance(v, str):
        print(f'{k}={v}')
    elif isinstance(v, bool):
        print(f'{k}={str(v).lower()}')
    elif isinstance(v, (int, float)):
        print(f'{k}={v}')
\" " & quoted form of configPath
		
		-- Apply each key=value pair to the matching variable
		repeat with configLine in paragraphs of configPairs
			set configLine to configLine as text
			if configLine is "" then
				-- skip empty lines
			else
				set delimOffset to offset of "=" in configLine
				set configKey to text 1 thru (delimOffset - 1) of configLine
				set configVal to text (delimOffset + 1) thru -1 of configLine
				
				if configKey is "mpvTabTitle" then set mpvTabTitle to configVal
				if configKey is "requiredNetwork" then set requiredNetwork to configVal
				if configKey is "speakerName" then set speakerName to configVal
				if configKey is "audioDelay" then set audioDelay to configVal
				if configKey is "dayVolume" then set dayVolume to (run script "return " & configVal)
				if configKey is "nightVolume" then set nightVolume to (run script "return " & configVal)
				if configKey is "dayStart" then set dayStart to configVal
				if configKey is "nightStart" then set nightStart to configVal
				if configKey is "maxVideoHeight" then set maxVideoHeight to (run script "return " & configVal)
				if configKey is "cacheSize" then set cacheSize to configVal
				if configKey is "cacheReadahead" then set cacheReadahead to configVal
				if configKey is "cachePauseWait" then set cachePauseWait to configVal
				if configKey is "targetLUFS" then set targetLUFS to configVal
				if configKey is "peakCeiling" then set peakCeiling to configVal
			end if
		end repeat
	end if
end try

-- =============================================================================
-- MAIN SCRIPT (wrapped in top-level error handler)
-- =============================================================================
try
	
	-- =========================================================================
	-- RESOLVE HOMEBREW PREFIX
	-- =========================================================================
	
	-- Detect Homebrew path (Apple Silicon: /opt/homebrew, Intel: /usr/local)
	set brewPrefix to do shell script "if [ -d /opt/homebrew ]; then echo '/opt/homebrew'; elif [ -d /usr/local/Cellar ]; then echo '/usr/local'; else echo ''; fi"
	if brewPrefix is "" then
		display dialog "Homebrew not found. Install it from https://brew.sh" buttons {"OK"} default button "OK"
		return
	end if
	set brewBin to brewPrefix & "/bin"
	
	-- =========================================================================
	-- DEPENDENCY CHECK
	-- =========================================================================
	
	set missingDeps to {}
	repeat with dep in {"mpv", "yt-dlp", "ffmpeg", "python3"}
		set depPath to do shell script "test -x " & quoted form of (brewBin & "/" & dep) & " && echo ok || echo missing"
		if depPath is "missing" then
			set end of missingDeps to dep as text
		end if
	end repeat
	
	if (count of missingDeps) > 0 then
		set AppleScript's text item delimiters to ", "
		set depList to missingDeps as text
		set AppleScript's text item delimiters to ""
		display dialog "Missing dependencies: " & depList & return & return & "Install with: brew install " & depList buttons {"OK"} default button "OK"
		return
	end if
	
	-- Detect available terminal (prefer iTerm, fall back to Terminal.app)
	set useiTerm to (do shell script "mdfind 'kMDItemCFBundleIdentifier == com.googlecode.iterm2' | head -1") is not ""
	
	-- =========================================================================
	-- WIFI CONNECTION (skip if requiredNetwork is empty)
	-- =========================================================================
	
	if requiredNetwork is not "" then
		-- Resolve WiFi interface dynamically (not always en0)
		set wifiInterface to do shell script "networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'"
		if wifiInterface is "" then
			display dialog "Could not find a Wi-Fi interface on this Mac" buttons {"OK"} default button "OK"
			return
		end if
		
		-- Verify current WiFi connection matches required network
		set currentNetwork to do shell script "ipconfig getsummary " & wifiInterface & " | grep '^ *SSID ' | sed 's/.*SSID : //'"
		if currentNetwork is not equal to requiredNetwork then
			-- Retrieve WiFi password from login keychain (stored by this script)
			set keychainService to "airplay-youtube-wifi-" & requiredNetwork
			set wifiPassword to ""
			set passwordFromKeychain to false
			try
				set wifiPassword to do shell script "security find-generic-password -s " & quoted form of keychainService & " -w 2>/dev/null"
				if wifiPassword is not "" then set passwordFromKeychain to true
			end try
			
			if wifiPassword is "" then
				-- No stored password — ask the user
				set passwordDialog to display dialog "Enter WiFi password for " & requiredNetwork & ":" default answer "" buttons {"Cancel", "OK"} default button "OK" with hidden answer
				set wifiPassword to text returned of passwordDialog
				if wifiPassword is "" then
					display dialog "No password entered" buttons {"OK"} default button "OK"
					return
				end if
			end if
			
			-- Connect to the specified network
			try
				do shell script "networksetup -setairportnetwork " & wifiInterface & " " & quoted form of requiredNetwork & " " & quoted form of wifiPassword
			on error
				-- Clear stored password so user is re-prompted next time
				if passwordFromKeychain then
					do shell script "security delete-generic-password -s " & quoted form of keychainService & " 2>/dev/null; true"
				end if
				display dialog "Failed to connect to " & requiredNetwork & ". Saved password has been cleared." buttons {"OK"} default button "OK"
				return
			end try
			
			-- Verify connection succeeded (retry up to 5 times)
			set connectionVerified to false
			set verifyNetwork to ""
			repeat 5 times
				delay 1
				try
					set verifyNetwork to do shell script "ipconfig getsummary " & wifiInterface & " | grep '^ *SSID ' | sed 's/.*SSID : //'"
					if verifyNetwork is equal to requiredNetwork then
						set connectionVerified to true
						exit repeat
					end if
				end try
			end repeat
			
			if not connectionVerified then
				set errMsg to "Could not verify WiFi network." & return & return & "Expected: " & requiredNetwork
				if verifyNetwork is not "" then
					set errMsg to errMsg & return & "Connected to: " & verifyNetwork
				end if
				display dialog errMsg buttons {"OK"} default button "OK"
				return
			end if
			
			-- Connection verified — save password to keychain for next time
			if not passwordFromKeychain then
				do shell script "security delete-generic-password -s " & quoted form of keychainService & " 2>/dev/null; true"
				do shell script "security add-generic-password -a " & quoted form of (do shell script "whoami") & " -s " & quoted form of keychainService & " -w " & quoted form of wifiPassword
			end if
		end if
	end if
	
	-- =========================================================================
	-- FIND YOUTUBE VIDEO IN BROWSERS
	-- =========================================================================
	
	-- Detect running browsers
	tell application "System Events"
		set appNames to name of every application process whose background only is false
	end tell
	set braveRunning to appNames contains "Brave Browser"
	set chromeRunning to appNames contains "Google Chrome"
	set safariRunning to appNames contains "Safari"
	
	if not braveRunning and not chromeRunning and not safariRunning then
		display dialog "No supported browser is running." & return & return & "Open a YouTube video in Brave, Chrome, or Safari." buttons {"OK"} default button "OK"
		return
	end if
	
	set ytTabs to {}
	set ytURLs to {}
	set ytTabRefs to {}
	set ytIsActive to {}
	set ytBrowsers to {}
	
	-- Helper: check if URL is a YouTube video (not Music)
	-- Used by all browser scan blocks below
	script ytHelper
		on isYouTubeVideo(tabURL)
			return (tabURL contains "youtube.com" or tabURL contains "youtu.be") and tabURL does not contain "music.youtube.com"
		end isYouTubeVideo
		
		on cleanTabTitle(rawTitle)
			set cleaned to rawTitle
			-- Strip " - YouTube" suffix
			if cleaned ends with " - YouTube" then
				set cleaned to text 1 thru -11 of cleaned
			end if
			-- Remove notification count prefix (e.g., "(1) " or "(23) ")
			set cleaned to do shell script "echo " & quoted form of cleaned & " | sed -E 's/^\\([0-9]+\\) //'"
			return cleaned
		end cleanTabTitle
	end script
	
	-- Scan Brave
	if braveRunning then
		tell application "Brave Browser"
			if (count of windows) > 0 then
				set activeTabURL to URL of active tab of front window
				repeat with w in windows
					repeat with t in tabs of w
						set tabURL to URL of t
						if ytHelper's isYouTubeVideo(tabURL) then
							set cleanTitle to ytHelper's cleanTabTitle(title of t)
							set end of ytTabs to cleanTitle
							set end of ytURLs to tabURL
							set end of ytTabRefs to t
							set end of ytIsActive to (tabURL is activeTabURL)
							set end of ytBrowsers to "brave"
						end if
					end repeat
				end repeat
			end if
		end tell
	end if
	
	-- Scan Chrome
	if chromeRunning then
		tell application "Google Chrome"
			if (count of windows) > 0 then
				set activeTabURL to URL of active tab of front window
				repeat with w in windows
					repeat with t in tabs of w
						set tabURL to URL of t
						if ytHelper's isYouTubeVideo(tabURL) then
							set cleanTitle to ytHelper's cleanTabTitle(title of t)
							set end of ytTabs to cleanTitle
							set end of ytURLs to tabURL
							set end of ytTabRefs to t
							set end of ytIsActive to (tabURL is activeTabURL)
							set end of ytBrowsers to "chrome"
						end if
					end repeat
				end repeat
			end if
		end tell
	end if
	
	-- Scan Safari (different API: name not title, current tab not active tab, do JavaScript not execute)
	if safariRunning then
		tell application "Safari"
			if (count of windows) > 0 then
				set activeTabURL to URL of current tab of front window
				repeat with w in windows
					repeat with t in tabs of w
						set tabURL to URL of t
						if ytHelper's isYouTubeVideo(tabURL) then
							set cleanTitle to ytHelper's cleanTabTitle(name of t)
							set end of ytTabs to cleanTitle
							set end of ytURLs to tabURL
							set end of ytTabRefs to t
							set end of ytIsActive to (tabURL is activeTabURL)
							set end of ytBrowsers to "safari"
						end if
					end repeat
				end repeat
			end if
		end tell
	end if
	
	if (count of ytTabs) is 0 then
		display dialog "No YouTube tabs found." & return & return & "Open a YouTube video in Brave, Chrome, or Safari." buttons {"OK"} default button "OK"
		return
	end if
	
	-- Selection priority: active tab > single tab > prompt
	set selectedURL to ""
	set selectedTab to missing value
	set selectedBrowser to ""
	
	if (count of ytTabs) is 1 then
		set selectedURL to item 1 of ytURLs
		set selectedTab to item 1 of ytTabRefs
		set selectedBrowser to item 1 of ytBrowsers
	else
		-- Check for an active YouTube tab (auto-select if exactly one)
		set activeIndex to 0
		set activeCount to 0
		repeat with i from 1 to count of ytTabs
			if item i of ytIsActive then
				set activeCount to activeCount + 1
				set activeIndex to i
			end if
		end repeat
		
		if activeCount is 1 then
			set selectedURL to item activeIndex of ytURLs
			set selectedTab to item activeIndex of ytTabRefs
			set selectedBrowser to item activeIndex of ytBrowsers
		else
			-- Prompt with numbered list showing browser tags
			set numberedTabs to {}
			repeat with i from 1 to count of ytTabs
				set browserTag to "[" & (item i of ytBrowsers) & "] "
				set end of numberedTabs to (i as text) & ". " & browserTag & item i of ytTabs
			end repeat
			set selectedItem to choose from list numberedTabs with prompt "Select a YouTube tab:" without multiple selections allowed
			if selectedItem is false then return
			set selectedIndex to (do shell script "echo " & quoted form of (item 1 of selectedItem) & " | cut -d'.' -f1") as integer
			set selectedURL to item selectedIndex of ytURLs
			set selectedTab to item selectedIndex of ytTabRefs
			set selectedBrowser to item selectedIndex of ytBrowsers
		end if
	end if
	
	-- Warn about YouTube Shorts
	if selectedURL contains "/shorts/" then
		set shortsChoice to button returned of (display dialog "This is a YouTube Shorts URL. Playback format selection may not work as expected. Continue?" buttons {"Cancel", "Continue"} default button "Continue")
		if shortsChoice is "Cancel" then return
	end if
	
	-- Pause video playback in browser
	-- Brave/Chrome require a tell block around the tab for execute javascript (the "in" parameter form fails silently)
	-- Safari uses "do JavaScript" instead of "execute javascript"
	if selectedBrowser is "brave" then
		try
			tell application "Brave Browser"
				tell selectedTab
					execute javascript "document.querySelector('video').pause();"
				end tell
			end tell
		end try
	else if selectedBrowser is "chrome" then
		try
			tell application "Google Chrome"
				tell selectedTab
					execute javascript "document.querySelector('video').pause();"
				end tell
			end tell
		end try
	else if selectedBrowser is "safari" then
		try
			tell application "Safari"
				tell selectedTab
					do JavaScript "document.querySelector('video').pause();"
				end tell
			end tell
		end try
	end if
	delay 0.5
	
	-- Extract timestamp parameter (e.g. t=268, t=268s, t=4m28s, t=1h2m3s) before stripping it
	set startTime to do shell script "echo " & quoted form of selectedURL & " | grep -oE '[?&]t=([^&]+)' | head -1 | sed 's/^[?&]t=//' | sed 's/h/ /g; s/m/ /g; s/s//g' | awk '{
		n = NF
		if (n == 1) print $1
		else if (n == 2) print $1*60 + $2
		else if (n == 3) print $1*3600 + $2*60 + $3
	}'"
	
	-- Strip timestamp parameter from URL and clean up malformed query strings
	set cleanURL to do shell script "echo " & quoted form of selectedURL & " | sed -E 's/([?&])t=[^&]*//g; s/\\?&/?/; s/\\?$//'"
	
	-- =========================================================================
	-- TERMINATE EXISTING MPV & PREPARE CONFIG
	-- =========================================================================
	
	-- Terminate any existing mpv processes
	set mpvRunning to do shell script "pgrep -x mpv || true"
	if mpvRunning is not "" then
		do shell script "killall mpv"
		delay 0.5
	end if
	
	-- Clean up stale IPC socket from previous run
	do shell script "rm -f /tmp/mpv-socket"
	
	-- Kill any leftover loudness analyzer from previous run
	do shell script "pkill -f mpv-loudness-analyzer || true"
	
	-- Create temporary mpv config directory (wipe and recreate to avoid stale files)
	set configDir to "/tmp/mpv-temp-config"
	do shell script "rm -rf " & quoted form of configDir
	do shell script "mkdir -p " & quoted form of configDir
	
	-- Create scripts directory for Lua scripts
	set scriptsDir to configDir & "/scripts"
	do shell script "mkdir -p " & quoted form of scriptsDir
	
	-- Create Lua script for pause/play OSD messages
	do shell script "cat > " & quoted form of (scriptsDir & "/pause-indicator.lua") & " << 'LUASCRIPT'
function on_pause_change(name, value)
    if value then
        mp.osd_message(\"Paused\", 1)
    else
        mp.osd_message(\"Playing\", 1)
    end
end

mp.observe_property(\"pause\", \"bool\", on_pause_change)
LUASCRIPT"
	
	-- Create Lua script for loudness analysis overlay
	-- Displays small status text in the bottom-left corner of the video
	do shell script "cat > " & quoted form of (scriptsDir & "/loudness-overlay.lua") & " << 'LUASCRIPT'
local overlay = mp.create_osd_overlay(\"ass-events\")
local clear_timer = nil

function show_loudness(text)
    if clear_timer then
        clear_timer:kill()
        clear_timer = nil
    end
    -- ASS tags: bottom-left (\\an1), small font (\\fs14), semi-transparent gray, thin border
    overlay.data = \"{\\\\an1\\\\fs14\\\\c&HBBBBBB&\\\\alpha&H40&\\\\bord1\\\\shad0}\" .. text
    overlay:update()
end

function clear_loudness()
    overlay:remove()
end

-- Listen for status updates from the analyzer script
mp.register_script_message(\"loudness-status\", function(text)
    show_loudness(text)
end)

-- Listen for final result (auto-clears after specified seconds)
mp.register_script_message(\"loudness-done\", function(text, seconds)
    show_loudness(text)
    local timeout = tonumber(seconds) or 5
    clear_timer = mp.add_timeout(timeout, clear_loudness)
end)
LUASCRIPT"
	
	-- Create mpv.conf (volume-max raised to 200 to allow gain boost up to +6 dB)
	do shell script "cat > " & quoted form of (configDir & "/mpv.conf") & " << 'MPVCONF'
volume-max=200
input-default-bindings=no
osc=no
border=no
title-bar=no
MPVCONF"
	
	-- Create input.conf with restricted keybindings
	do shell script "cat > " & quoted form of (configDir & "/input.conf") & " << 'INPUTCONF'
# Keyboard shortcuts
SPACE cycle pause
UP add volume 2
DOWN add volume -2
RIGHT seek 5
LEFT seek -5
Shift+RIGHT seek 60
Shift+LEFT seek -60
f cycle fullscreen
ESC set fullscreen no
q quit
m cycle mute
o show-progress

# Mouse actions
MBTN_LEFT ignore
MBTN_LEFT_DBL cycle fullscreen
INPUTCONF"
	
	-- =========================================================================
	-- CREATE LOUDNESS ANALYZER SCRIPT
	-- =========================================================================
	
	-- Background script that:
	-- 1. Downloads audio-only via yt-dlp piped directly to ffmpeg (nothing saved to disk)
	-- 2. Measures integrated LUFS and true peak via ebur128
	-- 3. Calculates a linear gain offset clamped by peak ceiling to prevent distortion
	-- 4. Gradually ramps mpv volume via IPC socket (no compression or dynamic processing)
	set analyzerScript to "/tmp/mpv-loudness-analyzer.sh"
	do shell script "cat > " & quoted form of analyzerScript & " << 'ANALYZER'
#!/usr/bin/env python3
\"\"\"
Volume adjustment for mpv. Runs as a background process.
- Downloads audio-only via yt-dlp piped to ffmpeg (nothing saved to disk)
- Measures integrated LUFS and true peak via ebur128
- Calculates a linear gain offset clamped by peak ceiling
- Adjusts mpv volume via IPC socket (no compression or dynamic processing)
\"\"\"
import sys, os, socket, json, time, math, subprocess, re, atexit
from datetime import datetime

URL = sys.argv[1]
TARGET_LUFS = float(sys.argv[2])
PEAK_CEILING = float(sys.argv[3])
BREW_BIN = sys.argv[4]
MPV_SOCKET = \"/tmp/mpv-socket\"
LOG = \"/tmp/mpv-loudness.log\"
ANALYSIS_TIMEOUT = 300  # 5 minute timeout for audio download + analysis

# ── Logging ──────────────────────────────────────────────────────────────────

log_file = open(LOG, \"w\")
atexit.register(log_file.close)

def log(msg):
    line = f\"{datetime.now().strftime('%H:%M:%S')} {msg}\"
    log_file.write(line + \"\\n\")
    log_file.flush()

# ── IPC helpers (single reusable connection) ─────────────────────────────────

mpv_sock = None

def mpv_connect():
    global mpv_sock
    mpv_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    mpv_sock.connect(MPV_SOCKET)
    mpv_sock.settimeout(1.0)

def mpv_cmd(command):
    \"\"\"Send a command to mpv via IPC. Returns True on success, False on failure.\"\"\"
    try:
        mpv_sock.send((json.dumps({\"command\": command}) + \"\\n\").encode())
        mpv_sock.recv(4096)
        return True
    except (ConnectionError, BrokenPipeError, OSError) as e:
        log(f\"IPC error: {e}\")
        return False

def osd(msg):
    log(f\"[OSD] {msg}\")
    mpv_cmd([\"script-message\", \"loudness-status\", msg])

def osd_done(msg, seconds=8):
    log(f\"[OSD] {msg} (clearing in {seconds}s)\")
    mpv_cmd([\"script-message\", \"loudness-done\", msg, str(seconds)])

# ── Main ─────────────────────────────────────────────────────────────────────

log(f\"===== Loudness Analysis: {datetime.now()} =====\")
log(f\"URL: {URL}\")
log(f\"Target: {TARGET_LUFS} LUFS, Peak ceiling: {PEAK_CEILING} dBTP\")

# Wait for mpv IPC socket (up to 15 seconds)
log(\"Waiting for mpv IPC socket...\")
for _ in range(15):
    if os.path.exists(MPV_SOCKET):
        try:
            mpv_connect()
            break
        except:
            pass
    time.sleep(1)
else:
    log(\"ERROR: mpv IPC socket not found after 15 seconds\")
    sys.exit(1)

log(\"mpv IPC socket ready\")
osd(\"Loudness: downloading and analyzing audio...\")

# Download audio-only piped directly to ffmpeg — nothing touches disk
# Uses subprocess list form to avoid shell injection via URL
log(\"Downloading audio-only stream and analyzing with ebur128...\")

yt_dlp = os.path.join(BREW_BIN, \"yt-dlp\")
ffmpeg = os.path.join(BREW_BIN, \"ffmpeg\")

yt_cmd = [yt_dlp, \"-f\", \"bestaudio\", \"--no-warnings\", \"-o\", \"-\", URL]
ff_cmd = [ffmpeg, \"-i\", \"pipe:0\", \"-af\", \"ebur128=peak=true\", \"-f\", \"null\", \"-\"]

yt_proc = subprocess.Popen(yt_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
ff_proc = subprocess.Popen(ff_cmd, stdin=yt_proc.stdout, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
yt_proc.stdout.close()  # Allow yt_proc to receive SIGPIPE if ff_proc exits

try:
    raw_output = ff_proc.communicate(timeout=ANALYSIS_TIMEOUT)[0].decode()
except subprocess.TimeoutExpired:
    ff_proc.kill()
    yt_proc.kill()
    ff_proc.communicate()
    yt_proc.communicate()
    log(\"ERROR: Audio analysis timed out after 5 minutes\")
    osd_done(\"Loudness: analysis timed out\", 5)
    sys.exit(1)

# Reap yt-dlp process to prevent zombie
yt_proc.wait()

# Take only the last 50 lines (the ebur128 summary)
analysis = \"\\n\".join(raw_output.strip().splitlines()[-50:])

log(\"Analysis complete, parsing results...\")

# Parse integrated LUFS and true peak — use last match to get the summary values,
# not per-segment values that appear earlier in the output
lufs_matches = re.findall(r\"I:\\s+(-?[\\d.]+)\", analysis)
peak_matches = re.findall(r\"Peak:\\s+(-?[\\d.]+)\", analysis)

measured_lufs = float(lufs_matches[-1]) if lufs_matches else None
true_peak = float(peak_matches[-1]) if peak_matches else None

log(f\"Measured LUFS: {measured_lufs if measured_lufs is not None else 'FAILED'}\")
log(f\"True peak: {true_peak if true_peak is not None else 'FAILED'}\")

if measured_lufs is None or true_peak is None:
    log(\"ERROR: Could not parse loudness values from ffmpeg output\")
    osd_done(\"Loudness: analysis failed\", 5)
    sys.exit(1)

# Calculate gain clamped by peak ceiling (boost only — never attenuate)
desired_gain = TARGET_LUFS - measured_lufs
max_gain = PEAK_CEILING - true_peak
final_gain = min(desired_gain, max_gain)

display_measured = f\"{measured_lufs:.1f}\"
display_peak = f\"{true_peak:.1f}\"

# Skip if volume is already at or above target, or boost is negligible
if final_gain < 0.5:
    log(f\"No boost needed (gain would be {final_gain:+.1f} dB), skipping\")
    osd_done(f\"Loudness: {display_measured} LUFS, peak {display_peak} dBTP\", 8)
    sys.exit(0)

new_vol = 100 * math.pow(10, final_gain / 20)
new_vol = max(10.0, min(200.0, round(new_vol, 1)))

display_gain = f\"{final_gain:+.1f}\"

log(f\"Boost: {display_gain} dB -> mpv volume: {new_vol}%\")

# Ramp volume: ~5s per 3dB, clamped 3-12s, ~15 steps/sec, single socket
duration = max(3.0, min(12.0, abs(final_gain) * 5.0 / 3.0))
steps = max(10, int(duration * 15))
interval = duration / steps

log(f\"Ramping volume from 100 to {new_vol}...\")
log(f\"Ramp duration: {round(duration, 1)}s\")

start_vol = 100.0
for i in range(1, steps + 1):
    vol = round(start_vol + (new_vol - start_vol) * i / steps, 1)
    if not mpv_cmd([\"set_property\", \"volume\", vol]):
        log(\"mpv IPC connection lost during ramp, aborting\")
        break
    time.sleep(interval)

log(\"Volume adjustment complete\")
osd_done(f\"Loudness: {display_measured} LUFS, peak {display_peak} dBTP, volume {display_gain} dB\", 8)
log(\"Done\")

try:
    mpv_sock.close()
except:
    pass
ANALYZER"
	do shell script "chmod +x " & quoted form of analyzerScript
	
	-- =========================================================================
	-- LAUNCH AIRFOIL (only if speaker routing is configured)
	-- =========================================================================
	
	set useAirfoil to (speakerName is not "")
	
	if useAirfoil then
		tell application "Airfoil"
			launch
		end tell
	end if
	
	-- =========================================================================
	-- START MPV IN TERMINAL
	-- =========================================================================
	
	-- Build mpv command with config variables
	set mpvCmd to brewBin & "/mpv" & ¬
		" --config-dir=" & quoted form of configDir & ¬
		" --input-ipc-server=/tmp/mpv-socket" & ¬
		" --autofit=90%" & ¬
		" --ytdl-format=\"bestvideo[height<=" & maxVideoHeight & "][vcodec^=avc]+bestaudio\"" & ¬
		" --hwdec=auto-safe" & ¬
		" --cache=yes" & ¬
		" --demuxer-max-bytes=" & cacheSize & ¬
		" --demuxer-readahead-secs=" & cacheReadahead & ¬
		" --cache-pause-initial=yes" & ¬
		" --cache-pause-wait=" & cachePauseWait & ¬
		" --msg-level=ffmpeg/video=error" & ¬
		" --ytdl-raw-options=retries=3"
	
	-- Apply audio delay only when routing through Airfoil (compensates AirPlay latency)
	if useAirfoil then
		set mpvCmd to mpvCmd & " --audio-delay=" & audioDelay
	end if
	
	-- Append start time if a timestamp was extracted from the URL
	if startTime is not "" then
		set mpvCmd to mpvCmd & " --start=" & startTime
	end if
	
	set mpvCmd to mpvCmd & " " & quoted form of cleanURL
	
	if useiTerm then
		-- ── iTerm path ──
		tell application "iTerm"
			launch
			
			-- Wait for iTerm to be fully running (maximum 10 attempts)
			set appReady to false
			repeat 10 times
				try
					if running then
						set appReady to true
						exit repeat
					end if
				end try
				delay 0.5
			end repeat
			
			if not appReady then
				display dialog "iTerm did not launch successfully" buttons {"OK"} default button "OK"
				return
			end if
			
			-- Create window if none exist
			if (count of windows) = 0 then
				create window with default profile
			end if
			
			-- Search for existing mpv tab across all windows
			set foundTab to false
			set targetWindow to missing value
			set targetTab to missing value
			
			repeat with w in windows
				repeat with aTab in tabs of w
					tell aTab
						tell current session
							if name contains mpvTabTitle then
								set foundTab to true
								set targetWindow to w
								set targetTab to aTab
								exit repeat
							end if
						end tell
					end tell
				end repeat
				if foundTab then exit repeat
			end repeat
			
			if foundTab then
				-- Reuse existing mpv tab: interrupt any running process, then clear
				tell targetWindow
					tell targetTab
						select
						tell current session
							write text (ASCII character 3) -- Send Ctrl+C
							delay 0.3
							write text "clear"
						end tell
					end tell
				end tell
			else
				-- Create new tab with custom title in current window
				tell current window
					create tab with default profile
					delay 0.3
					tell current session
						write text "echo -ne \"\\e]1;" & mpvTabTitle & "\\a\"; clear"
					end tell
				end tell
			end if
			
			-- Execute mpv
			tell current window
				tell current session
					write text mpvCmd
				end tell
			end tell
		end tell
	else
		-- ── Terminal.app fallback ──
		tell application "Terminal"
			activate
			
			-- Search for existing mpv tab
			set foundTab to false
			set targetWindow to missing value
			
			if (count of windows) > 0 then
				repeat with w in windows
					repeat with t in tabs of w
						if custom title of t contains mpvTabTitle then
							set foundTab to true
							set targetWindow to w
							-- Bring this tab to front
							set selected tab of w to t
							-- Kill any running process and clear
							do script (ASCII character 3) in t
							delay 0.3
							do script "clear" in t
							exit repeat
						end if
					end repeat
					if foundTab then exit repeat
				end repeat
			end if
			
			if not foundTab then
				-- Create a new window or tab
				if (count of windows) = 0 then
					do script ""
				else
					tell application "System Events"
						tell process "Terminal"
							keystroke "t" using command down
						end tell
					end tell
					delay 0.3
				end if
				-- Set custom title for future identification
				set custom title of selected tab of front window to mpvTabTitle
			end if
			
			-- Execute mpv
			do script mpvCmd in selected tab of front window
		end tell
	end if
	
	-- =========================================================================
	-- WAIT FOR MPV WINDOW & CONFIGURE AIRFOIL
	-- =========================================================================
	
	-- Wait for mpv window to appear (with early exit detection)
	set mpvWindowVisible to false
	repeat 10 times
		delay 1
		
		-- Check if mpv process is still alive
		set mpvAlive to do shell script "pgrep -x mpv || echo 'dead'"
		if mpvAlive is "dead" then
			display dialog "mpv exited unexpectedly. Check the terminal for error details." buttons {"OK"} default button "OK"
			return
		end if
		
		-- Check for mpv window existence via System Events
		try
			set windowCheck to do shell script "osascript -e 'tell application \"System Events\" to return exists (first window of process \"mpv\" whose subrole is \"AXStandardWindow\")'"
			if windowCheck is "true" then
				set mpvWindowVisible to true
				exit repeat
			end if
		end try
	end repeat
	
	if mpvWindowVisible then
		-- Configure audio routing through Airfoil (only if speaker is configured)
		if useAirfoil then
			-- Resolve speaker volume based on time of day
			set currentHour to hours of (current date)
			set currentMin to minutes of (current date)
			set nowMins to currentHour * 60 + currentMin
			
			set AppleScript's text item delimiters to ":"
			set dayParts to text items of dayStart
			set nightParts to text items of nightStart
			set AppleScript's text item delimiters to ""
			set dayMins to ((item 1 of dayParts) as integer) * 60 + ((item 2 of dayParts) as integer)
			set nightMins to ((item 1 of nightParts) as integer) * 60 + ((item 2 of nightParts) as integer)
			
			if dayMins < nightMins then
				-- Normal case: day 07:00 → 23:30
				if nowMins ≥ dayMins and nowMins < nightMins then
					set speakerVolume to dayVolume
				else
					set speakerVolume to nightVolume
				end if
			else
				-- Inverted case: day wraps past midnight (e.g. day=22:00, night=06:00)
				if nowMins ≥ nightMins and nowMins < dayMins then
					set speakerVolume to nightVolume
				else
					set speakerVolume to dayVolume
				end if
			end if
			
			tell application "Airfoil"
				-- Specify mpv as audio source
				set pathToApp to brewBin & "/mpv"
				
				-- Initialize and configure audio source
				set newSource to make new application source
				set application file of newSource to pathToApp
				
				-- Activate the audio source
				set (current audio source) to newSource
				
				-- Configure speaker volume
				set (volume of every speaker) to speakerVolume
				
				-- Verify target speaker exists and connect
				if (count of (every speaker whose name is speakerName)) is 0 then
					display dialog "Speaker \"" & speakerName & "\" not found. Audio will play locally." buttons {"OK"} default button "OK"
				else
					connect to (every speaker whose name is speakerName)
					
					-- Verify the speaker actually connected
					delay 2
					if not (connected of (first speaker whose name is speakerName)) then
						display dialog "Speaker \"" & speakerName & "\" failed to connect. Audio may play locally." buttons {"OK"} default button "OK"
					end if
				end if
			end tell
		end if
		
		-- Launch background loudness analysis (audio-only, nothing saved to disk)
		do shell script quoted form of analyzerScript & " " & quoted form of cleanURL & " " & targetLUFS & " " & peakCeiling & " " & quoted form of brewBin & " &> /dev/null &"
		
		-- Hide background applications to keep focus on video
		tell application "System Events"
			if useiTerm then
				set visible of process "iTerm2" to false
			else
				set visible of process "Terminal" to false
			end if
			if useAirfoil then
				set visible of process "Airfoil" to false
			end if
		end tell
	else
		display dialog "mpv window did not appear within 10 seconds" buttons {"OK"} default button "OK"
	end if
	
on error errMsg number errNum
	display dialog "Script error: " & errMsg & " (" & errNum & ")" buttons {"OK"} default button "OK"
end try