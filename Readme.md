# Big Fake Nixie Tube Clock

A 4-digit clock that simulates large Nixie tubes. Each digit is an 800×320px LCD screen inside a glass dome, animating realistic cross-fading images of Nixie digits.

Hardware: **ULX3S ECP5-12K FPGA + ESP32**. The FPGA drives the displays; the ESP32 handles timekeeping and connectivity.

---

## Prerequisites

- **Windows 10/11** with WSL2 (Ubuntu 22.04 recommended)
- **Docker Desktop** configured to use the WSL2 backend
- **VS Code** with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- **usbipd-win** — installed automatically on first run of `launch.ps1`

---

## First-time setup

### 1. Build the Docker image

Open a WSL2 terminal and run from the repo root:

```bash
docker build -t ulx3s-toolchain .
```

This compiles all tools from source (Yosys, nextpnr-ecp5, openFPGALoader, Verilator, ESP-IDF). **It takes a long time** — 30–60 minutes depending on your machine. A smoke-test at the end prints tool versions to confirm success.

You only need to rebuild when the `Dockerfile` changes.

### 2. One-time USB setup (Windows only)

The ULX3S board needs to be shared with WSL2 via usbipd. Plug in the board, then run from an **admin PowerShell prompt** once:

```powershell
winget install usbipd          # if not already installed
usbipd list                    # find the busid for VID 0403 / PID 6015
usbipd bind --busid <busid>    # e.g. 6-4
```

After this, `launch.ps1` handles everything without admin rights.

---

## Daily workflow

### Starting the container (Windows)

Run from a normal (non-admin) PowerShell prompt:

```powershell
.\launch.ps1
```

This attaches the ULX3S to WSL2 via usbipd and drops you into a shell inside the container, with the repo mounted at `/workspace`.

### Starting the container (WSL / Linux)

```bash
bash launch.sh
```

### Opening in VS Code

With the board plugged in and the container running, open VS Code and use:

**F1 → Dev Containers: Reopen in Container**

VS Code will connect to the container. The repo is at `/workspace` inside it.

Alternatively, open VS Code first and let it prompt you to reopen in the container automatically (it detects `.devcontainer/devcontainer.json`).

---

## Source layout

```
src/
  fpga-blinker/   — Verilog project (FPGA HDL), built with Yosys + nextpnr
  blinker/        — ESP-IDF project (ESP32 firmware)
```

---

## Building and flashing

All commands run **inside the container** from the relevant `src/` subdirectory.

### FPGA

```bash
cd /workspace/src/fpga-blinker
make          # synthesise + place & route → blinker.bit
make flash    # load bitstream into FPGA SRAM (lost on power cycle)
make flash-persistent   # write bitstream to SPI flash (survives power cycles)
```

### ESP32

```bash
cd /workspace/src/blinker
idf.py build                        # compile firmware → build/blinker.bin
esp32-flash build/blinker.bin       # load passthru onto FPGA, then flash ESP32
```

The `esp32-flash` script loads the passthru bitstream onto the FPGA first (which bridges USB-serial through to the ESP32), then uses esptool.py to program the firmware.

---

## Toolchain inside the container

| Tool | Purpose |
|---|---|
| **Yosys** | HDL synthesis (Verilog / SystemVerilog) |
| **nextpnr-ecp5** | Place & route for ECP5 FPGAs |
| **Project Trellis** | ECP5 bitstream database |
| **openFPGALoader** | Bitstream programming over USB |
| **Verilator** | Verilog simulation |
| **ESP-IDF v5.2.3** | ESP32 firmware toolchain |
| **esptool.py** | ESP32 flashing utility |

---

## Troubleshooting

### `launch.ps1` fails with "Device in error state"

The FTDI stub driver got into a bad state (usually after an unclean shutdown). The script will automatically trigger an elevated unbind+rebind — approve the UAC prompt. If it keeps failing, unplug and replug the board.

**To avoid this on exit:** before closing your WSL session, run:
```powershell
usbipd detach --busid <busid>
```

### Device shows as "Shared" not "Attached" after `launch.ps1` exits

This is normal — usbipd detaches the device when the WSL session ends.

### `make flash` fails with "unable to open ftdi device"

The ULX3S isn't attached to WSL2. Run `launch.ps1` first (or `usbipd attach --wsl --busid <busid>` manually).

### Docker image is out of date

```bash
docker build -t ulx3s-toolchain .
```
