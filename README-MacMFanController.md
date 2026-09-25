# Mac M Fan Controller

Mac M Fan Controller is a small macOS menu bar app for controlling fans on Apple Silicon Macs through [`smctl`](https://github.com/leaperone/smctl). It provides quick fan presets, manual RPM control, live temperature monitoring, and simple auto-trigger rules for GPU and CPU temperatures.

The app is named for M-series Macs because its backend and sensor parsing are built around Apple Silicon `smctl` output. It is not intended to claim Intel Mac support.

## Features

- Menu bar app with no Dock window.
- Fan presets: `20%`, `40%`, `50%`, `80%`, and `MAX`.
- Manual RPM controls for synced fans or independent fan `0` / fan `1` control.
- One-click `Reset to Auto`.
- Live polling through `smctl sensors`.
- Temperature display for:
  - CPU Die, from keys such as `Tp0D` or `TC0D`
  - GPU Proximity, from `Tg0P`
- Auto-trigger rules for GPU and CPU Die:
  - enable or disable each rule
  - edit the trigger temperature with the `Temp` field
  - choose a preset
  - optionally type an exact RPM override

## Requirements

- macOS 13 or newer
- Apple Silicon Mac
- Xcode command line tools if rebuilding from source
- `smctl` installed and configured

Install the backend:

```bash
brew install leaperone/smctl/smctl
sudo smctl daemon install
```

Confirm `smctl` can see your sensors:

```bash
smctl sensors
```

## Running

Double-click:

```text
MacMFanController.app
```

The app appears as a fan item in the macOS menu bar.

## Controls

`Sync both fans` applies a preset or manual RPM to all available fans.

`Independent` exposes separate controls for fan `0` and fan `1`. If your Mac only has one fan, fan `1` commands may fail or be ignored by `smctl`.

Manual RPM values are clamped to `1200` through `7000`.

## Auto Rules

Auto rules are evaluated every 5 seconds after fresh sensor data is read.

Each rule has:

- an enable switch
- an editable `Temp` field
- an output row with preset dropdown and optional RPM field
- a mode label showing whether the rule is using the preset percentage or the RPM override

If the RPM field is filled in, the app uses that RPM instead of the preset. Repeated triggers at the same output are ignored so the app does not keep sending the same fan command every poll.

## Building

From this folder:

```bash
xcrun swiftc -O -parse-as-library MacMFanController.swift \
  -o MacMFanController.app/Contents/MacOS/MacMFanController
```

The app bundle expects this executable:

```text
MacMFanController.app/Contents/MacOS/MacMFanController
```

Run the rule logic tests:

```bash
CLANG_MODULE_CACHE_PATH=/tmp swift Tests/RuleLogicTests.swift
```

## Safety

Manual fan control can interfere with macOS thermal management. Use conservative RPMs, keep an eye on temperatures, and use `Reset to Auto` when you are done.
