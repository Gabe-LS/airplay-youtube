# onedrive-shared-downloader

Download all files from a shared OneDrive folder link — including all subfolders.

> **Note:** tested on macOS only. Should work on Linux and Windows but has not been verified.

---

## Before you start — check Python is installed

You need **Python 3.10 or later** on your computer.

**macOS:** open the Terminal app (press `Command + Space`, type `Terminal`, press Enter), then type:

```
python3 --version
```

**Windows:** press `Windows + R`, type `cmd`, press Enter, then type:

```
python --version
```

If you see `Python 3.10` or a higher number, you're good. If you see `Python 2.x`, an error, or nothing — download and install Python 3 from [python.org](https://www.python.org/downloads/).

> **Windows tip:** during the Python installation, make sure to check the box that says **"Add Python to PATH"** — without this, the commands in this guide will not work.

---

## Step 1 — Download the tool

1. Click the green **Code** button at the top of this page
2. Click **Download ZIP**
3. Unzip the downloaded file — you'll get a folder called `onedrive-shared-downloader-main`
4. Remember where you saved that folder — you'll need it in the next step

---

## Step 2 — Open a terminal in the tool folder

**macOS:**
1. Open the **Terminal** app — press `Command + Space`, type `Terminal`, press Enter
2. Open **Finder** and navigate to the `onedrive-shared-downloader-main` folder — it should be in your `Downloads` folder
3. In Terminal, type `cd ` (the letters c, d, and a space — do not press Enter yet)
4. Click on the `onedrive-shared-downloader-main` folder in Finder, then drag it into the Terminal window — the folder path will appear automatically after `cd `
5. Press Enter

**Windows:**
1. Open **File Explorer** — press `Windows + E` or click the folder icon in the taskbar
2. Navigate to the `onedrive-shared-downloader-main` folder — it should be in your `Downloads` folder
3. Click once on the address bar at the top of the File Explorer window (the bar that shows the folder path — it will turn blue and show the full path)
4. Type `cmd` (replacing whatever was there) and press Enter — a Command Prompt window will open in the right folder

---

## Step 3 — Install

In the terminal you opened in Step 2, type the following command and press Enter:

**macOS / Linux:**
```
python3 install.py
```

**Windows:**
```
python install.py
```

The installer will show you what it is about to do and ask:

```
Continue? [y/N]
```

Type `y` and press Enter to proceed.

It will download and set up everything automatically. This may take a few minutes depending on your internet speed. **You only need to do this once.**

---

## Step 4 — Download

First, get your OneDrive link. Use the original shared link you received — it should look something like:

```
https://1drv.ms/f/c/abc123/...
```

Then, in the terminal (open it again following Step 2 if you closed it), type the following command, replacing the example URL with the link you just copied.

**macOS / Linux** — the URL must be inside single quotes:
```
python3 run.py 'https://1drv.ms/f/c/...'
```

**Windows** — the URL must be inside double quotes:
```
python run.py "https://1drv.ms/f/c/..."
```

Press Enter. The tool will start downloading and show a progress display. Depending on the number and size of the files, this may take a while — you can leave it running in the background.

By default, files are saved to a folder called `onedrive_download` inside your Downloads folder:
- **macOS / Linux:** `~/Downloads/onedrive_download`
- **Windows:** `C:\Users\your-username\Downloads\onedrive_download` (replace `your-username` with your Windows username)

### Saving to a different folder

Add the destination path after the URL:

**macOS / Linux:**
```
python3 run.py 'https://1drv.ms/f/c/...' ~/Desktop/my-folder
```

**Windows** — replace `your-username` with your Windows username:
```
python run.py "https://1drv.ms/f/c/..." C:\Users\your-username\Desktop\my-folder
```

### If the download is interrupted

Just run the same command again — the tool will automatically skip files that are already downloaded and continue from where it left off.

---

## Uninstall

Open a terminal in the tool folder (follow Step 2 again), then run:

**macOS / Linux:**
```
python3 uninstall.py
```

**Windows:**
```
python uninstall.py
```

The tool will show you what it is about to remove and ask for confirmation before doing anything. Your downloaded files are not affected.

---

## Something not working?

Open an issue at [github.com/Gabe-LS/onedrive-shared-downloader/issues](https://github.com/Gabe-LS/onedrive-shared-downloader/issues)

---

## Features

- Downloads all files in all subfolders automatically
- Resumes interrupted downloads — if it stops, just run it again
- Skips files that are already downloaded
- Downloads up to 4 files at the same time
- Ctrl+C stops safely — run again to continue where you left off

---

## Technical details

<details>
<summary>Click to expand</summary>

**How it works**

OneDrive shared links require authentication even for public shares. This tool opens the link in a headless Chromium browser, intercepts the temporary Badger auth token and API endpoints that the page uses, and reuses them directly to fetch file listings and download URLs.

This relies on undocumented Microsoft internals that may change at any time. If the tool stops working, try running it again — a fresh token is acquired on every invocation.

**Limitations**

- Tested on macOS only
- The auth token lasts approximately 7 days. For very large downloads that span multiple days, re-run the script — it will skip already-completed files and continue
- Downloads are not cryptographically verified. Files are trusted by size
- Progress bars on Windows require Windows 10 version 1511 or later

**Advanced users**

If you want to use a pre-existing virtual environment, activate it before running `install.py` and `run.py`.

</details>

---

## License

MIT License — Copyright (c) 2026 Gabriele Lo Surdo

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
