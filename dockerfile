# ULX3S Toolchain Dockerfile
# Fetches the install script from the ULX3S toolchain repository and runs it
# to set up the environment.
# See https://github.com/ulx3s/ulx3s-toolchain

FROM ubuntu:22.04

# Set timezone to avoid tzdata prompts
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install base dependencies for the install.sh script
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    cmake \
    python3 python3-pip python3-setuptools python3-wheel \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Fetch only the install script
WORKDIR /opt/ulx3s-toolchain
RUN wget https://raw.githubusercontent.com/ulx3s/ulx3s-toolchain/master/install.sh && \
    chmod +x install.sh

# Run the install script
RUN ./install.sh aptget barebones

RUN export WORKSPACE=~/ULX3S_workspace && \
    cd "$WORKSPACE"/ulx3s-toolchain && \
    ./install_litex.sh && \
    ./install_litex-ulx3s.sh && \
    ./install_esp32.sh

# Add toolchain to PATH (in case install.sh puts binaries under /usr/local/bin)
ENV PATH="/usr/local/bin:$PATH"

# Default workspace
WORKDIR /workspace
CMD ["/bin/bash"]
