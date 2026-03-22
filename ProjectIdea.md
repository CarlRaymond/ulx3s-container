# Big Fake Nixie Tube Clock

This goal of this project is to build a 4-digit clock that simulates large Nixie tubes. Each "tube"
is a tall LCD screen, 800x320px, inside a glass dome. The screens will animate images of Nixie digits,
realistically cross-fading from one to the next.

This will be a collaboration with Claude Code, to learn how to use it effectively, and discover its
capabilities.

## Hardware

The main controller is a ULX3S FPGA development board (https://radiona.org/ulx3s/#about). It
contains a Lattice ECP5 FPGA (12K LUTs), a 32MB SDRAM chip (W9825G6KH-6), ESP32-WROVER-E microcontroller,
a real-time clock with battery backup, and a Micro-SD card slot.

The displays are 6.5" Color Bar TFT LCD IoT Display 800x320 Pixels, ER-TFT065-1-2476, from BuyDisplay.com
(https://www.buydisplay.com/6-5-inch-color-bar-tft-lcd-iot-display-800x320-pixels-with-optl-touch-sceen.)

A main circuit board, to be designed, will supply the various voltages needed from an external 12Vdc
supply, and connect to daughter boards on each display. The board-to-board conneciton may be 40-pin, 80-conductor IDE cables. They may have local power supplies for each digit. The main board will also
have a WWVB receiver module, EverSet ES-100 WWVB BPSK Phase Modulation Receiver (interfaced over i2c),
to keep the clock accurate
(https://www.universal-solder.ca/product/everset-es100-mod-wwvb-bpsk-phase-modulation-receiver-module/)

The main board will have a simple multiplexing arrangement so that the four diplays can be driven in
sequence. A target frame rate goal is 15 frame/sec per display, requiring 60 frames/sec coming out of 
the controller.

The daughter boards, to be mounted on each display, will have a 50-pin flat-flex connector for the display,
and a 40-pin IDE connector to connect to the main board. (Proposed. The actual cable used may be different.)
The cable will carry the video input and DC power (at multiple voltages) to the display.

Circuit boards will be designed in KiCad, and manufactured by PCBway or JLCPCB or similar.

## Theory of Operation

The clock is under control of the ESP-32 microcontroller. On startup, it will:

* Read a configuration file from the SD card, which specifies the digit images to use
* Load images from the SD card into the SDRAM (10 images, plus an "all digits off" image, and possibly a few others)
* Read the current time from the WWVB receiver, and set the on-board RTC
* At each minute, trigger the FPGA to generate the animation from one digit to the next

The controller can also run a simple web interface over WiFi so it can be controlled at a distance.

The FPGA's job is to feed video to the four digits, and generate the in-between frames as one digit
transitions to the next. The 32MB SDRAM is too small to hold animations; it just contains static
images. The animation sequences are created on-the-fly. The displays require 24-bits at a time,
and a few more signals. There aren't enough GPIO pins on the FPGA, so it will multiplex them in
round-robin fashion.

## Development Process

### Establish a Portable Development Environment

The development environment is a Docker container with a full toolchain for the ULX3S: Yosys, nextpnr,
openFPGALoader, Verilog, and higher-level tools to design the SDRAM interface.

We will build in steps. First get the development environment established, with scripts that can
ensure the host system has any necessary tools first (for example, using USB inside a container
running under WSL) and run necessary commands in the host operating system before launching the
container. We want to be sure the development environment will just work on different computers
without having to install tools or configure settings manually.

### Exercise the ULX3S
Then we will exercise the development environment to make sure we compile test projects for the FPGA
and microcontroler, get them loaded onto the board, and verify.

Next we can build a web server on the ESP-32 to control it and act as a better interface than a serial
port. However, diagnostics over a serial port may be useful for the automated design-build-upload-test
cycle.

### Image Generation Process
We will create the digit images using Inkscape, and build a script to generate the individual digit
images from a master file. Inkscape files are XML, and can be manipulated externally to turn layers
on or off, or apply settings, etc. A real Nixie tube stacks the 10 filaments one in front of the next,
and the unlit filaments are visible over and under the currently lit filament. Each digit filament will
be a layer of the Inkscape file, with a background layer behind them all, and a foreground layer
with a thin hexagonal grid over all the filaments, just like a real Nixie.

Once a master image consisting of 10 filament shapes, background and foreground layers, and parameters
for the appearance of lit and unlit paths, a script will iterate through the digits and create a file
for each, then use Inkscape's command line interface to load it and save in a bitmap format. It may
be necessary to convert the output format to something suitable with ImageMagick.

### Dev-Board Only Milestone

Before any new hardware is ready, a significant milestone that only relies on the development board
alone will be to simulate the basic operation of the clock, just without a display:

* ESP-32 reads configuration from the SD card, and loads a set of digits into the SDRAM
* Control the FPGA to generate the inbetween frames (for example, build a frame that is
30% of digit 1 combined with 70% of digit 2) and write them back to SDRAM
* ESP-32 reads the generated frames from SDRAM and stored them on the SD card
* The web server on the ESP-32 creates a page showing all the generated frames

### Design the Hardware

#### Power Supply
The first task is to design the power supply. The system will run from an external 12Vdc 2A supply.
From that we will need various voltages for the ULX3S and for the LCD display. The displays have 
a variable backlight that will be under control of the ESP-32. A suitable PWM ciruit for that will
be needed. Somewhere there will be an ambient light sensor so we can automatically brigten or dim the
backlight as room illumination changes.

A goal is that the clock use as little power as possible, so that it is practical to leave it running
24 hours a day without worrying about power consumption. A target is 10W on average over a 24-hour
cycle.

#### Main Board
The main board will hold the power supply, the WWVB receiver, a connector for the ambient light sensor,
and connectors four the four display boards. The ULX3S will mount to the main board using two 40-pin
connectors. For durability, the socket will be mounted on the ULX3S, and pin headers on the main
board. There will be multiple versions of the main board, and frequently swapping boards may lead
to bent pins. Better that happens on the external board than on the ULX3S.

The main board may need to be larger than the ULX3S to accommodate the connectors for the display board.
In the extreme, it could span the width of the finished clock, acting as a backplane for the display
boards.

#### Display Board
 The displays have a 50-pin, 0.5mm pitch flat flex cable, but the cable is too short to bring to
 the main board. Each display will be mounted on a circuit board with a FFC connector, and another
 connector going back to the main board. A large number of signals are neede (24 for data, control
 signals, and power). An old 40-position IDE cable might do the job. The later 80-wire version might
 be a good choice, because there is a ground wire between every signal wire to reduce crosstalk.
 That may be good to have for video data rates. They are cheap and readily available.

The PWM circuit for the backlight may live on this board, or there might be a single backlight
PWM circuit on the main board supplying all the display.

 The display board may also have some RGB LEDs for backlight effects. That will consume a few pins.







