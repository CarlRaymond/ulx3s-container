# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a development environment and source tree for the **Big Fake Nixie Tube Clock** — a 4-digit clock that simulates large Nixie tubes using tall LCD screens (800×320px) inside glass domes, animating and cross-fading digit images.

The hardware is a **ULX3S ECP5-12K FPGA + ESP32** board. The FPGA drives the displays; the ESP32 handles timekeeping and connectivity. The `Dockerfile` defines the full toolchain container used for all development.

## Repository Layout

```
Dockerfile          — full from-source build of the FPGA/ESP32 toolchain
launch.ps1          — Windows: attach ULX3S over USB to WSL2 and launch container
launch.sh           — WSL/Linux: run the container with USB passthrough
setup-usb.ps1       — Windows: one-time usbipd install + device bind (self-elevating)
src/
  blinker/          — ESP-IDF project (ESP32 firmware)
  fpga-blinker/     — Verilog project (FPGA HDL)
```

## What the Container Provides

All tools are built from source (GitHub `--depth 1` clones) inside the image:

| Tool | Purpose |
|---|---|
| **Yosys** | HDL synthesis (Verilog / SystemVerilog) |
| **nextpnr-ecp5** | Place & route for ECP5 FPGAs |
| **Project Trellis** | ECP5 bitstream database (required by nextpnr) |
| **openFPGALoader** | Bitstream programming over USB |
| **Verilator** | Verilog simulation |
| **ESP-IDF v5.2.3** | ESP32 firmware toolchain (pinned tag) |
| **esptool.py** | ESP32 flashing utility |

A convenience script `/usr/local/bin/esp32-flash` is baked in; it loads the passthru bitstream onto the FPGA, then flashes an ESP32 firmware binary.

## Building the Image

```bash
docker build -t ulx3s-toolchain .
```

The build takes a long time (compiles all tools from source). A smoke-test at the end of the Dockerfile prints versions of all key tools to verify the build succeeded.

## Launching from Windows (normal workflow)

Run from a normal (non-admin) PowerShell prompt:

```powershell
.\launch.ps1
```

This finds the ULX3S (VID `0403`, PID `6015`), attaches it to WSL2 via usbipd, and starts the container. On first run it calls `setup-usb.ps1` which self-elevates via UAC to install usbipd and bind the device — subsequent launches need no admin rights.

If the FTDI stub driver gets into an error state (e.g. after an unclean shutdown), `launch.ps1` automatically triggers an elevated unbind+rebind and retries.

**Clean shutdown:** before closing WSL, run:
```powershell
usbipd detach --busid <busid>
```
This avoids leaving the driver in an error state and prevents a UAC prompt on the next launch.

## Launching from WSL / Linux

```bash
bash launch.sh
```

Runs the container with `--privileged` and `/dev/bus/usb` mounted for USB access.

## USB / udev Rules

The ULX3S uses an FT231X USB-serial chip (VID `0403`, PID `6015`). To program from inside the container on a Linux host, copy the bundled udev rules to the host:

```bash
docker cp <container>:/etc/udev/rules.d/80-ulx3s.rules /etc/udev/rules.d/
udevadm control --reload
```

## ESP32 Flashing Workflow

The FPGA must be loaded with the passthru bitstream before programming the ESP32 (it bridges USB-serial through to the ESP32). The `esp32-flash` script handles this automatically:

```bash
esp32-flash firmware.bin [/dev/ttyUSB0]
```

The passthru bitstream is downloaded at build time to `/opt/ulx3s/passthru_12k.bit`. If the download fails during build, provide the file manually.

## Dev Container

The `.devcontainer/devcontainer.json` configures VS Code to open this repo inside the container. It references `../dockerfile` (lowercase) — the file on disk is `Dockerfile` (uppercase); verify case matches your OS when editing.
