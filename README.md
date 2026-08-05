# ProTee AutoStart

Hands-off startup for golf simulator bays. When the sim PC boots, ProTee AutoStart watches the screen, clicks through the GSPro startup flow, and leaves the bay sitting at the practice range — ready for whoever walks in. No staff member has to log in, find the mouse, and start the sim every morning.

Built by BA Custom Products and free to use.

## What it does

On startup it works through the sequence on its own:

1. Dismisses the GSPro update prompt if one appears (clicks Download Update and waits for it to finish).
2. Clicks Play! on the GSPro Configuration window.
3. Selects PRACTICE, then opens the practice range.
4. Optionally clicks your player tab in ProTee (for example, your name) if you set one.
5. Leaves GSPro focused at the range, parks the mouse out of the way in a corner, and resets the aim.

If your launch monitor fails to connect, it can power-cycle the monitor through a Shelly smart plug and retry, so a flaky connection doesn't leave the bay dead in the morning.

It reads the screen using the OCR built into Windows, so it clicks the words that are actually on screen rather than firing blind clicks at fixed coordinates. That makes it tolerant of small differences in layout and load timing from one machine to the next.

While the sequence runs, a small BA Custom Products banner sits along the bottom edge of the GSPro screen. It stays clear of every button the tool needs to click and goes away as soon as the bay is ready.

## Requirements

- A Windows PC running your simulator (Windows 10 or 11).
- GSPro.
- Optional: a Shelly smart plug on the launch monitor's power, if you want automatic connection recovery.

You do **not** need AutoHotkey installed to run the compiled `.exe` — it's self-contained. If you'd rather run the script directly, see [Running the script](#running-the-script-instead-of-the-exe) below.

## Install

1. Download the latest `ProTeeAutoStart-x.x.x.zip` from the [Releases](../../releases) page.
2. Extract it somewhere permanent, for example `C:\ProTeeAutoStart\`. Each release lists the SHA-256 of the `.exe` so you can verify your download is genuine.
3. Run `ProTeeAutoStart.exe` once. The Setup window opens — fill in your settings and click Save.
4. Add it to Windows startup so it runs on boot: press `Win + R`, type `shell:startup`, and drop a shortcut to the `.exe` into that folder.

That's it. The next time the PC boots, it runs on its own.

## Everyday use

When it launches normally (from the Startup folder) it waits out a short countdown and then runs.

- Press `S` during the countdown to open Setup.
- Press `ESC` at any time to abort the sequence.

## Settings

Everything is in the Setup window:

- **Shelly plug IP** — the IP of the smart plug powering your launch monitor. Used for automatic connection recovery. Leave it blank if you're not using that.
- **Profile / player tab** — the player tab the tool clicks in ProTee, for example your name. Leave it blank to skip that step.
- **ProTee window title** — optional. Helps the tool anchor to the ProTee tab/status window. The default works for a standard install.
- **Timing (seconds)**
  - *Plug OFF duration* — how long to cut power during a recovery.
  - *Wait after power ON* — pause after restoring power.
  - *Wait for reconnect* — how long to wait for the monitor to reconnect.
  - *Overall timeout* — when to give up on the whole sequence and alert.
  - *Pre-click pause (ms)* — delay after moving the cursor before clicking. Raise it on slower machines.
- **Alert webhook URL** — optional. If the sequence times out, it pings this URL (a Twilio number, a webhook relay, etc.) so you know a bay needs a look.
- **Banner display monitor** — which screen the banner sits on. `Auto` follows GSPro automatically and is right for almost everyone. You can also force a monitor number (`1`, `2`, ...), or set it to `Off`.
- **Stop at the GSPro main menu** — tick this if you'd rather the bay finish on the GSPro main menu instead of going into the practice range. The tool still clicks Play and waits for the launch monitor to connect; it just stops at the menu and brings GSPro to the front so the ProTee connector window isn't sitting on top of it.

There are test buttons next to the settings: Test Power-Cycle fires the Shelly once so you can confirm the wiring, Test Screen Read runs a single OCR pass and shows what the tool currently sees, and Start Sequence Now runs the full sequence immediately without rebooting.

Settings are saved to `Documents\BA Custom Products\ProTee Auto-Start\`.

## Running the script instead of the .exe

Some machines block unsigned `.exe` files. If yours does, you can run the AutoHotkey script directly:

1. Install [AutoHotkey v1.1](https://www.autohotkey.com/) (the classic v1 branch, not v2).
2. Download `ProTeeAutoStart.ahk` from this repository.
3. Double-click it to run, or put a shortcut to it in `shell:startup`.

The script behaves the same as the `.exe`. The image files in this repository (`ba_logo_white.png`, `ba_logo_black.png`, `ba_qr.png`) are optional — the script runs fine without them and simply shows text where the images would be.

## Compile it yourself (optional)

Prefer to build the `.exe` from source? Everything you need is in this repository:

1. Install [AutoHotkey v1.1](https://www.autohotkey.com/), which includes the Ahk2Exe compiler.
2. Put `ProTeeAutoStart.ahk`, `ProTeeAutoStart.ico`, and the three `.png` files in one folder.
3. Open Ahk2Exe, select the script, choose the **ANSI 32-bit** base file, leave compression **off**, and compile.

The icon, version info, and images are picked up automatically from directives inside the script, so your build comes out identical to a release build.

## A note on the SmartScreen warning

The `.exe` isn't code-signed yet, so Windows SmartScreen may show a blue "Windows protected your PC" box the first time you run it. That's normal for small unsigned tools. Click **More info**, then **Run anyway**. If Windows quarantined the file, right-click it, choose **Properties**, tick **Unblock**, and click OK.

## How it stays safe to leave running unattended

- It clicks specific on-screen words rather than blind coordinates.
- `ESC` aborts instantly.
- An overall timeout stops it if something is wrong, and it can alert you over a webhook.
- The banner is pinned to the bottom strip, clear of every button it reads or clicks.

## About BA Custom Products

We build and share tools for golf simulator operators — booking systems you run on your own branded site, control-box hardware, and automation like this one. ProTee AutoStart is free; if it saves you time, take a look at what else we make.

[www.bacustomproducts.com](https://www.bacustomproducts.com)

## License

MIT — free to run, share, and adapt for your own facility. See [LICENSE](LICENSE).
