# ProTee AutoStart

Hands-off startup for golf simulator bays. ProTee AutoStart watches the screen, clicks through the GSPro startup flow, and leaves the bay sitting at the practice range (or the GSPro main menu, if you prefer), ready for whoever walks in. No staff member has to log in, find the mouse, and start the sim every morning.

> **Free, and built by people who run golf sim bays.** If ProTee AutoStart saves you time, the best way to say thanks is to check out our **golf sim control boxes** and other simulator gear at **[bacustomproducts.com](https://www.bacustomproducts.com)**. Those sales are what keep tools like this free.

## What it does

When it runs, it works through the sequence on its own:

1. Clicks through the ProTee update prompt if one appears (clicks Download Update and waits for it to finish).
2. Clicks Play! on the GSPro Configuration window.
3. Selects PRACTICE, then opens the practice range.
4. Optionally clicks your player tab in ProTee (for example, your name) if you set one.
5. Leaves GSPro focused at the range, parks the mouse out of the way in a corner, and resets the aim.

If your launch monitor fails to connect, it can power-cycle the monitor through a Shelly smart plug and retry, so a flaky connection doesn't leave the bay dead in the morning.

It reads the screen using the OCR built into Windows, so it clicks the words that are actually on screen rather than firing blind clicks at fixed coordinates. That makes it tolerant of differences in layout, resolution, display scaling and load timing from one machine to the next.

While the sequence runs, a small BA Custom Products banner sits along the bottom edge of the GSPro screen. It stays clear of every button the tool needs to click and goes away as soon as the bay is ready.

## Requirements

- A Windows PC running your simulator (Windows 10 or 11).
- GSPro and ProTee Labs.
- Optional: a Shelly smart plug on the launch monitor's power, if you want automatic connection recovery.

You do **not** need AutoHotkey installed to run the compiled `.exe` — it's self-contained. If you'd rather run the script directly, see [Running the script](#running-the-script-instead-of-the-exe) below.

## Install

1. Download the latest installer, `ProTeeAutoStart-Setup-x.x.x.zip`, from the [Releases](../../releases) page.
2. Extract it and run the setup.
   - Starting it with Windows? Keep **Start automatically when you log in** ticked. That's the usual way to run it on a bay PC.
   - Starting it from a game launcher or kiosk instead? Untick it, and have your launcher run `ProTeeAutoStart.exe /run`.
3. Open **ProTee AutoStart Setup** from the Start Menu, fill in your settings, and click Save. (The very first time the program runs, Setup also opens on its own.)

Each release lists the SHA-256 of the download so you can verify it's genuine. Prefer no installer? `ProTeeAutoStart-x.x.x.zip` on the same page is the bare program. Extract it somewhere permanent, run it once to open Setup, then drop a shortcut into `shell:startup` (or point your launcher at it with `/run`).

## Everyday use

Started from Windows startup, it shows a short countdown and then runs. Press `S` during the countdown to open Setup, or `ESC` to cancel. Started with `/run`, it skips the countdown and runs straight away.

While the sequence is running:

- **`ESC` stops it at any time** — including while the mouse and keyboard are paused, and even if AutoStart itself has frozen.
- **`Ctrl+Shift+D` kills it instantly**, too.
- **If AutoStart ever stops responding for 30 seconds, it is closed automatically**, so a bay can never be left stuck. (Change the 30 with `FreezeKillSec` in `settings.ini`.)

`Ctrl+Alt+Del` always works as well.

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
- **Pause the mouse and keyboard while it runs** — tick this so a player who walks up early can't click or type over the tool while it's working. It's a guide, not a lock: the tool's own clicks still go through, `ESC` and `Ctrl+Shift+D` still stop it, it needs no administrator rights, and everything comes back the moment the tool finishes, times out, or closes.

There are test buttons next to the settings: Test Power-Cycle fires the Shelly once so you can confirm the wiring, Test Screen Read runs a single OCR pass and shows what the tool currently sees, and Start Sequence Now runs the full sequence immediately without rebooting.

Settings and the activity log are saved in `Documents\BA Custom Products\ProTee Auto-Start\`.

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

The icon, version info, and images are picked up automatically from directives inside the script, so your build runs exactly the same program as a release build. (Its SHA-256 won't match the release, because the compiler pads each build slightly differently.)

## A note on the SmartScreen warning

The `.exe` isn't code-signed yet, so Windows SmartScreen may show a blue "Windows protected your PC" box the first time you run it. That's normal for small unsigned tools. Click **More info**, then **Run anyway**. If Windows quarantined the file, right-click it, choose **Properties**, tick **Unblock**, and click OK.

## How it stays safe to leave running unattended

- Where a button belongs to Windows — like Play on the GSPro Configuration dialog — it asks Windows for that button's exact position rather than reading the screen. That makes it immune to display scaling, resolution, monitor count, and anything sitting on top of the window.
- Everywhere else it clicks specific on-screen words rather than blind coordinates.
- A small watchdog runs alongside it. `ESC` always stops the tool through the watchdog, even if the tool itself has frozen, and the watchdog closes the tool on its own if it stops responding.
- An overall timeout stops it if something is wrong, and it can alert you over a webhook.
- The banner is pinned to the bottom strip, clear of every button it reads or clicks.

## About BA Custom Products

We build golf simulator hardware and software for facilities and home bays:

- **Control boxes** — physical button panels wired to drive your sim software, so players never need a keyboard.
- **Booking systems** — reservations and payments on your own branded site.
- **Automation tools** — like this one.

ProTee AutoStart is free. If it helps your bay, please take a look at what else we make:

**[www.bacustomproducts.com](https://www.bacustomproducts.com)**

## License

MIT — free to run, share, and adapt for your own facility. See [LICENSE](LICENSE).
