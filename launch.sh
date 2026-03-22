#!/bin/sh
docker run -it --rm \
    --privileged \
    -v /dev/bus/usb:/dev/bus/usb \
    -v $(pwd):/workspace \
    ulx3s-toolchain
