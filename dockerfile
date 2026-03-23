# ============================================================
# ULX3S ECP5-12K FPGA + ESP32 Toolchain
# Tools: Yosys · nextpnr-ecp5 · openFPGALoader · Verilator
#        ESP-IDF · esptool.py
# HDL:   Verilog / SystemVerilog
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ------------------------------------------------------------
# System dependencies
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential clang cmake git wget curl pkg-config \
    # Yosys deps
    bison flex libreadline-dev gawk tcl-dev libffi-dev \
    graphviz xdot python3 python3-dev python3-pip \
    libboost-all-dev zlib1g-dev \
    # nextpnr deps
    libeigen3-dev \
    # openFPGALoader deps
    libftdi1-2 libftdi1-dev libhidapi-libusb0 libhidapi-dev \
    libudev-dev libusb-1.0-0-dev \
    # Verilator deps
    perl help2man \
    # ESP-IDF deps
    python3-venv ninja-build ccache dfu-util \
    libusb-1.0-0 libssl-dev \
    # Useful extras
    make udev ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# nextpnr requires CMake ≥ 3.25; Ubuntu 22.04 ships 3.22.1
RUN pip3 install cmake

WORKDIR /build

# ------------------------------------------------------------
# 1. Project Trellis  (ECP5 database — required by nextpnr)
# ------------------------------------------------------------
RUN git clone --depth 1 --recurse-submodules \
        https://github.com/YosysHQ/prjtrellis.git && \
    cd prjtrellis/libtrellis && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local . && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# 2. Yosys  (synthesis)
# ------------------------------------------------------------
RUN git clone --depth 1 --recurse-submodules https://github.com/YosysHQ/yosys.git && \
    cd yosys && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# 3. nextpnr-ecp5  (place & route)
# ------------------------------------------------------------
RUN git clone --depth 1 --recurse-submodules https://github.com/YosysHQ/nextpnr.git && \
    cd nextpnr && \
    mkdir build && cd build && \
    cmake \
        -DARCH=ecp5 \
        -DTRELLIS_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_GUI=OFF \
        .. && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# 4. openFPGALoader  (bitstream programming via USB)
# ------------------------------------------------------------
RUN git clone --depth 1 https://github.com/trabucayre/openFPGALoader.git && \
    cd openFPGALoader && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# 5. Verilator  (simulation)
# ------------------------------------------------------------
RUN git clone --depth 1 https://github.com/verilator/verilator.git && \
    cd verilator && \
    autoconf && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install

# ------------------------------------------------------------
# USB / udev rules for ULX3S (FT231X chip, VID 0403 PID 6015)
# These rules are copied into the image for reference; to take
# effect on the HOST, copy them from the container:
#   docker cp <container>:/etc/udev/rules.d/80-ulx3s.rules \
#             /etc/udev/rules.d/ && udevadm control --reload
# ------------------------------------------------------------
RUN echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="664", GROUP="dialout"' \
        > /etc/udev/rules.d/80-ulx3s.rules && \
    echo 'ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", GROUP="dialout", MODE="666"' \
        >> /etc/udev/rules.d/80-ulx3s.rules

# ------------------------------------------------------------
# 6. ESP-IDF  (ESP32 firmware toolchain)
#    Pinned to a stable release; change the tag as needed.
# ------------------------------------------------------------
ENV IDF_PATH=/opt/esp/idf
ENV IDF_TOOLS_PATH=/opt/esp/tools

RUN mkdir -p /opt/esp && \
    git clone --depth 1 --branch v5.2.3 --recurse-submodules \
        https://github.com/espressif/esp-idf.git ${IDF_PATH} && \
    ${IDF_PATH}/install.sh esp32 && \
    # Make the IDF environment available in every shell
    echo "source ${IDF_PATH}/export.sh" >> /etc/bash.bashrc

# esptool is also installed standalone for quick flashing
RUN pip3 install esptool

# ------------------------------------------------------------
# 7. ULX3S passthru bitstream
#    The FPGA must be loaded with this before programming the
#    ESP32 — it bridges the USB-serial port through to the ESP32.
# ------------------------------------------------------------
RUN mkdir -p /opt/ulx3s && \
    wget -O /opt/ulx3s/passthru_ulx3s_v20_12k.bit \
        https://github.com/emard/ulx3s-bin/raw/master/fpga/passthru/passthru-v20-12f/passthru_ulx3s_v20_12k.bit && \
    test -s /opt/ulx3s/passthru_ulx3s_v20_12k.bit

# ------------------------------------------------------------
# 8. ULX3S self-test bitstream
# ------------------------------------------------------------
RUN wget -O /opt/ulx3s/selftest-mcp7940n.bin \
    https://github.com/emard/ulx3s-bin/raw/master/fpga/f32c/f32c-bin/selftest-mcp7940n.bin && \
    test -s /opt/ulx3s/selftest-mcp7940n.bin

# Convenience script: flash passthru then program ESP32
RUN cat <<'EOF' > /usr/local/bin/esp32-flash
#!/bin/bash
# Usage: esp32-flash <firmware.bin> [port]
set -e
PORT="${2:-/dev/ttyUSB0}"
BITSTREAM="/opt/ulx3s/passthru_ulx3s_v20_12k.bit"

echo ">>> Loading passthru bitstream onto FPGA..."
openFPGALoader -b ulx3s "$BITSTREAM"

# After openFPGALoader, the FT231X is in bit-bang mode. A USB reset puts
# it back to default UART mode and triggers ftdi_sio to auto-bind.
# Docker's /dev is isolated so we also need to create the device node.
python3 - <<'PYEOF'
import fcntl, glob, os, time

# Find FTDI device
for idv in glob.glob('/sys/bus/usb/devices/*/idVendor'):
    if open(idv).read().strip() != '0403': continue
    devdir = os.path.dirname(idv)
    if open(os.path.join(devdir, 'idProduct')).read().strip() != '6015': continue
    bus = int(open(os.path.join(devdir, 'busnum')).read())
    dev = int(open(os.path.join(devdir, 'devnum')).read())
    path = '/dev/bus/usb/%03d/%03d' % (bus, dev)
    with open(path, 'wb') as f:
        fcntl.ioctl(f, 0x5514, 0)   # USBDEVFS_RESET
    print('USB reset sent to', path)
    break

# Wait for reenumeration and ftdi_sio to auto-bind
time.sleep(2)

# Find the ttyUSB device from sysfs and create its node in Docker's /dev
for tty in glob.glob('/sys/class/tty/ttyUSB*'):
    dev_str = open(os.path.join(tty, 'dev')).read().strip()
    major, minor = (int(x) for x in dev_str.split(':'))
    name = '/dev/' + os.path.basename(tty)
    if not os.path.exists(name):
        os.mknod(name, 0o666 | 0o020000, os.makedev(major, minor))
        print('Created', name)
PYEOF
echo ">>> Waiting for $PORT..."
for i in $(seq 1 10); do
    [ -e "$PORT" ] && break
    sleep 1
done
if [ ! -e "$PORT" ]; then
    echo "Error: $PORT did not appear. Available ports:"
    ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  (none)"
    exit 1
fi

echo ">>> Flashing ESP32 firmware: $1"
esptool.py --port "$PORT" --baud 921600 \
    --before default_reset --after hard_reset \
    write_flash -z 0x1000 "$1"
echo ">>> Done!"
EOF
RUN chmod +x /usr/local/bin/esp32-flash

# ------------------------------------------------------------
# Clean up build artefacts
# ------------------------------------------------------------
RUN rm -rf /build

# ------------------------------------------------------------
# Default working directory for user projects
# ------------------------------------------------------------
WORKDIR /workspace

# Smoke-test: print versions of all key tools
RUN echo "=== Toolchain versions ===" && \
    yosys --version && \
    nextpnr-ecp5 --version && \
    openFPGALoader --Version && \
    verilator --version && \
    esptool.py version

CMD ["/bin/bash"]
