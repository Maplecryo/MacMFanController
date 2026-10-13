# Mac M Fan Controller

Mac M Fan Controller is a small macOS menu bar app for controlling fans on Apple Silicon Macs through [`smctl`](https://github.com/leaperone/smctl). It provides quick fan presets, manual RPM control, live temperature monitoring, and simple auto-trigger rules for GPU and CPU temperatures.

This app supports Apple Silicon Macs (M-series chips). Intel Mac support is not included.

## Features

- Menu bar app with no Dock window.
- Fan presets: `20%`, `40%`, `50%`, `80%`, and `MAX`.
- Typed manual RPM controls for synced fans or independent fan `0` / fan `1` control.
- One-click `Reset to Auto`.
- Live polling through `smctl sensors`.
- Temperature display for:
  - CPU Die, from keys such as `Tp0D` or `TC0D`
  - GPU Proximity, from `Tg0P`
- Auto-trigger rules for GPU and CPU Die:
  - enable or disable each rule
  - edit the trigger temperature with the `Temp` field
  - choose a percentage preset
  - optionally enter an exact direct RPM override

## Requirements

- macOS 13 or newer
- Apple Silicon Mac
- Xcode command line tools if rebuilding from source
- `smctl` installed and configured

Install the backend through Terminal:

```bash
brew install leaperone/smctl/smctl
sudo smctl daemon install
```

Confirm `smctl` can see your sensors:

```bash
smctl sensors
```

## Running

For the easiest setup, download a release archive, keep `Install.command` next to `MacMFanController.app`, and double-click `Install.command`. It copies the app to `/Applications`, installs the `smctl` backend when Homebrew is already installed, configures its service, and launches the app.

If Homebrew is not installed, the installer opens the official Homebrew website. Install Homebrew, then double-click `Install.command` again.

You may be asked for your Mac login password while the backend service is configured. This is required by `smctl` and macOS; the app itself does not collect or store the password.

To launch manually after installation:

```text
MacMFanController.app
```

The app appears as a fan item in the macOS menu bar.

## Controls

The synced mode label adapts to the hardware: it says `Sync fan` with one fan and `Sync fans` with two or more. It applies a preset or manual RPM to all available fans.

`Independent` exposes separate controls for every detected fan, including Fan 2 and higher on Macs with more than two fans. Macs with one physical fan show a notice that Independent mode is unavailable and keep the usable fan controls visible. Fanless Macs show that no controllable fans were detected and disable fan commands.

Manual RPM values are typed directly and clamped to `1200` through `7000` when applied.


## Auto Rules

Auto rules are evaluated every 5 seconds after fresh sensor data is read.

Each rule has:

- an enable switch
- an editable `Temp` field
- a percentage preset dropdown
- an optional `Direct RPM` override field, clamped to `1200` through `7000`

If the Direct RPM field is blank, the rule uses the selected percentage preset. If it contains a value, the direct RPM overrides the preset. Repeated triggers at the same output are ignored so the app does not keep sending the same fan command every poll.

## Building

From this folder:

```bash
./build.sh
```

The script builds the arm64 executable, removes Finder metadata that can block signing, and applies an ad-hoc signature for local use. The checked-in app bundle is suitable for development and testing. A public release should use Developer ID signing and notarization, then publish the resulting archive as a GitHub Release.

The app bundle contains the executable at:

```text
MacMFanController.app/Contents/MacOS/MacMFanController
```

Run the rule logic tests:

```bash
CLANG_MODULE_CACHE_PATH=/tmp swift Tests/RuleLogicTests.swift
CLANG_MODULE_CACHE_PATH=/tmp swift Tests/AutoRuleTests.swift
```

## Safety

Manual fan control can interfere with macOS thermal management. Use conservative RPMs, keep an eye on temperatures, and use `Reset to Auto` when you are done.
