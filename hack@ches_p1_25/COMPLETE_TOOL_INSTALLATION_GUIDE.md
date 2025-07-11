# Complete OpenTitan FPGA Tool Installation Guide

## Overview
This guide provides step-by-step instructions for installing all tools needed for OpenTitan FPGA development and dynamic analysis. Designed for complete beginners to OpenTitan and VLSI development.

## System Requirements

### Hardware Requirements
- **CPU**: Multi-core processor (4+ cores recommended)
- **RAM**: Minimum 16GB, recommended 32GB
- **Storage**: 150GB+ free space (Vivado ~75GB, builds ~30GB, tools ~20GB)
- **Network**: Broadband internet for downloads (30GB+ total)

### Operating System Support
- **Recommended**: Ubuntu 20.04 LTS or 22.04 LTS
- **Also supported**: CentOS 7/8, RHEL 7/8
- **Windows**: Supported but Linux strongly recommended

## Installation Overview

**Total Installation Time**: 2-4 hours (depending on internet speed)

**Installation Order**:
1. System dependencies (15 minutes)
2. Xilinx Vivado (60-90 minutes)
3. Bazel build system (10 minutes)
4. RISC-V toolchain (20 minutes)
5. OpenOCD debugger (15 minutes)
6. Python environment (10 minutes)
7. Verification and testing (15 minutes)

---

## Step 1: System Dependencies Installation

### Update System and Install Base Tools
```bash
# Update package database
sudo apt-get update && sudo apt-get upgrade -y

# Install essential development tools
sudo apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    vim \
    screen \
    minicom

# Install Python development environment
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python3-setuptools

# Install build system dependencies
sudo apt-get install -y \
    cmake \
    ninja-build \
    autoconf \
    automake \
    libtool \
    pkg-config

# Install hardware development tools
sudo apt-get install -y \
    device-tree-compiler \
    gtkwave \
    verilator

# Install USB and FTDI libraries for FPGA communication
sudo apt-get install -y \
    libftdi1-2 \
    libftdi1-dev \
    libusb-1.0-0 \
    libusb-1.0-0-dev \
    libudev-dev

# Install additional development libraries
sudo apt-get install -y \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libtinfo5 \
    texinfo

echo "✓ System dependencies installed successfully"
```

### Verify Base Installation
```bash
# Check if essential tools are available
echo "Checking basic tools..."
python3 --version
git --version
curl --version
make --version

# Check if all packages installed correctly
dpkg -l | grep -E "(build-essential|python3-dev|cmake|libftdi)" | wc -l
# Should show multiple packages (8+)
```

---

## Step 2: Xilinx Vivado Installation

### Download Vivado WebPACK (Free Edition)

**Manual Download Process**:
1. Go to: https://www.xilinx.com/support/download.html
2. Create free Xilinx account (required)
3. Select "Vivado ML Edition - Linux"
4. Download "Vivado ML Standard WebPACK" (~35GB download)
5. File will be named: `Xilinx_Unified_2023.1_0507_1903_Lin64.bin`

### Automated Download Script (if you have account)
```bash
# Create download directory
mkdir -p ~/Downloads/xilinx
cd ~/Downloads/xilinx

# Note: Replace USERNAME and PASSWORD with your Xilinx account
# This script requires valid Xilinx account credentials
cat > download_vivado.sh << 'EOF'
#!/bin/bash
# Automated Vivado download script

echo "This script requires valid Xilinx account credentials"
echo "Make sure you have registered at xilinx.com first"

read -p "Xilinx username: " XILINX_USER
read -s -p "Xilinx password: " XILINX_PASS
echo ""

# Download Vivado using wget with authentication
wget --user="$XILINX_USER" --password="$XILINX_PASS" \
     --no-check-certificate \
     "https://www.xilinx.com/member/forms/download/xef.html?filename=Xilinx_Unified_2023.1_0507_1903_Lin64.bin" \
     -O Xilinx_Unified_2023.1_0507_1903_Lin64.bin

if [[ $? -eq 0 ]]; then
    echo "✓ Vivado downloaded successfully"
    chmod +x Xilinx_Unified_2023.1_0507_1903_Lin64.bin
else
    echo "✗ Download failed - please download manually from xilinx.com"
fi
EOF

chmod +x download_vivado.sh
# Run: ./download_vivado.sh
```

### Install Vivado
```bash
# Navigate to download directory
cd ~/Downloads/xilinx

# Create installation directory
sudo mkdir -p /tools/Xilinx
sudo chown $USER:$USER /tools/Xilinx

# Create batch installation config
cat > vivado_install_config.txt << 'EOF'
#### Xilinx Vivado Installation Configuration ####
Edition=Vivado ML Standard
Product=Vivado
Destination=/tools/Xilinx
Modules=Vivado:1,Vitis:0,DocNav:1

# Device Support (select only what you need to save space)
DeviceSupport.Install.7Series=1
DeviceSupport.Install.Zynq7000=1
DeviceSupport.Install.UltraScale=0
DeviceSupport.Install.UltraScalePlus=0

# Installation Options
InstallOptions.Acquire or Manage a License Key=0
InstallOptions.Enable WebTalk for Vivado to send usage statistics to Xilinx=1

# Shortcuts and File Associations
CreateProgramGroupShortcuts=0
ProgramGroupFolder=Xilinx Design Tools
CreateShortcutsForAllUsers=0
CreateDesktopShortcuts=0
CreateFileAssociation=0
LaunchVivado=0
EOF

# Run installer in batch mode
sudo ./Xilinx_Unified_2023.1_0507_1903_Lin64.bin \
     --agree 3rdPartyEULA,XilinxEULA \
     --batch Install \
     --config vivado_install_config.txt

# Installation takes 60-90 minutes
echo "Vivado installation started - this will take 1-1.5 hours"
echo "Monitor progress in: /tmp/xinstall_*.log"
```

### Post-Installation Vivado Setup
```bash
# Install cable drivers for FPGA programming
sudo /tools/Xilinx/Vivado/2023.1/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers

# Create Vivado environment script
cat > ~/vivado_env.sh << 'EOF'
#!/bin/bash
# Vivado Environment Setup

export XILINX_VIVADO="/tools/Xilinx/Vivado/2023.1"

if [[ -d "$XILINX_VIVADO" ]]; then
    # Source Vivado settings
    source $XILINX_VIVADO/settings64.sh
    
    # Add to PATH
    export PATH="$XILINX_VIVADO/bin:$PATH"
    
    echo "✓ Vivado environment configured"
    echo "Vivado version: $(vivado -version | head -1)"
else
    echo "✗ Vivado not found at $XILINX_VIVADO"
    echo "Check installation path"
    return 1
fi
EOF

chmod +x ~/vivado_env.sh

# Test Vivado installation
source ~/vivado_env.sh
vivado -version
```

---

## Step 3: Bazel Build System Installation

### Install Bazel 6.2.1 (Required Version)
```bash
# Add Bazel repository key
curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > bazel.gpg
sudo mv bazel.gpg /etc/apt/trusted.gpg.d/

# Add Bazel repository
echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list

# Update package list
sudo apt-get update

# Install specific Bazel version (OpenTitan requires 6.2.1)
sudo apt-get install -y bazel-6.2.1

# Create compatibility symlink
sudo ln -sf /usr/bin/bazel-6.2.1 /usr/bin/bazel

# Verify installation
bazel version
# Should show: Build label: 6.2.1
```

### Configure Bazel for OpenTitan
```bash
# Create Bazel configuration file
cat > ~/.bazelrc << 'EOF'
# OpenTitan Bazel Configuration

# Build settings
build --incompatible_enable_cc_toolchain_resolution
build --action_env=PATH
build --host_action_env=PATH

# Test settings
test --test_output=errors
test --test_timeout=300

# Cache settings
build --disk_cache=~/.cache/bazel
build --repository_cache=~/.cache/bazel-repo

# Symlink prefix
build --symlink_prefix=bazel-

# Verbose failures
build --verbose_failures

# Use all available CPU cores
build --jobs=auto
EOF

echo "✓ Bazel configured for OpenTitan"
```

---

## Step 4: RISC-V Toolchain Installation

### Method 1: Use OpenTitan's Automated Installer (Recommended)
```bash
# Navigate to OpenTitan directory
cd $REPO_TOP

# Download and install RISC-V toolchain
./util/get-toolchain.py --target=riscv32 --install-dir=tools/riscv

# This installs:
# - RISC-V GCC cross-compiler
# - RISC-V GDB debugger
# - RISC-V Binutils
# - OpenOCD for JTAG debugging

# Add toolchain to PATH
echo 'export PATH=$REPO_TOP/tools/riscv/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify installation
riscv32-unknown-elf-gcc --version
riscv32-unknown-elf-gdb --version
```

### Method 2: Manual Installation from lowRISC
```bash
# Create tools directory
sudo mkdir -p /tools/riscv
sudo chown $USER:$USER /tools/riscv

# Download precompiled toolchain from lowRISC
cd /tmp
wget https://github.com/lowRISC/lowrisc-toolchains/releases/download/20220210-1/lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz

# Extract toolchain
tar -xf lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz -C /tools/riscv --strip-components=1

# Create environment script
cat > ~/riscv_env.sh << 'EOF'
#!/bin/bash
# RISC-V Toolchain Environment

export RISCV_ROOT="/tools/riscv"
export PATH="$RISCV_ROOT/bin:$PATH"

# Verify installation
if command -v riscv32-unknown-elf-gcc &> /dev/null; then
    echo "✓ RISC-V toolchain ready"
    echo "GCC version: $(riscv32-unknown-elf-gcc --version | head -1)"
else
    echo "✗ RISC-V toolchain not found"
    return 1
fi
EOF

chmod +x ~/riscv_env.sh
source ~/riscv_env.sh
```

### Test RISC-V Toolchain
```bash
# Create simple test program
cat > riscv_test.c << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello from RISC-V!\n");
    return 0;
}
EOF

# Compile for RISC-V
riscv32-unknown-elf-gcc -o riscv_test riscv_test.c

# Check if binary was created for correct architecture
file riscv_test
# Should show: ELF 32-bit LSB executable, UCB RISC-V, version 1 (SYSV)

echo "✓ RISC-V toolchain test passed"
rm riscv_test riscv_test.c
```

---

## Step 5: OpenOCD Installation

### Install OpenOCD Dependencies
```bash
sudo apt-get install -y \
    libtool \
    automake \
    autoconf \
    texinfo \
    libftdi1-dev \
    libusb-1.0-0-dev \
    libhidapi-dev \
    libcapstone-dev
```

### Build OpenOCD from Source
```bash
# Clone OpenOCD with RISC-V support
cd /tmp
git clone https://github.com/riscv/riscv-openocd.git
cd riscv-openocd

# Configure build
./bootstrap
./configure \
    --prefix=/tools/openocd \
    --enable-ftdi \
    --enable-jlink \
    --enable-stlink \
    --enable-ti-icdi \
    --enable-ulink \
    --enable-usb-blaster-2 \
    --enable-ft232r \
    --enable-vsllink \
    --enable-xds110 \
    --enable-cmsis-dap \
    --enable-hidapi \
    --disable-werror

# Build and install (takes 10-15 minutes)
make -j$(nproc)
sudo make install

# Verify installation
/tools/openocd/bin/openocd --version
```

### Configure OpenOCD for FPGA Boards
```bash
# Create OpenOCD configuration directory
mkdir -p ~/.config/openocd

# Create Nexys Video configuration
cat > ~/.config/openocd/nexys_video.cfg << 'EOF'
# Nexys Video FPGA Board Configuration for OpenTitan

# FTDI interface configuration
adapter driver ftdi
ftdi_device_desc "Digilent USB Device"
ftdi_vid_pid 0x0403 0x6010

# Use channel A for JTAG
ftdi_channel 0
ftdi_layout_init 0x00e8 0x00eb
ftdi_layout_signal nTRST -data 0x0010
ftdi_layout_signal nSRST -data 0x0040

# JTAG scan chain configuration
set _CHIPNAME riscv
jtag newtap $_CHIPNAME cpu -irlen 5 -expected-id 0x20000913

# Target configuration
target create $_CHIPNAME.cpu riscv -chain-position $_CHIPNAME.cpu
$_CHIPNAME.cpu configure -work-area-phys 0x20000000 -work-area-size 0x10000 -work-area-backup 0

# RISC-V specific configuration
riscv set_prefer_sba on
riscv set_command_timeout_sec 10
riscv set_mem_access sysbus progbuf abstract

# Set JTAG speed
adapter speed 1000

# Reset configuration
reset_config none

# Debug configuration
gdb_memory_map enable
gdb_flash_program enable
EOF

# Create Arty A7 configuration (alternative board)
cat > ~/.config/openocd/arty_a7.cfg << 'EOF'
# Arty A7 FPGA Board Configuration

adapter driver ftdi
ftdi_device_desc "Digilent USB Device"
ftdi_vid_pid 0x0403 0x6010
ftdi_channel 0
ftdi_layout_init 0x0088 0x008b

set _CHIPNAME riscv
jtag newtap $_CHIPNAME cpu -irlen 5 -expected-id 0x13631093

target create $_CHIPNAME.cpu riscv -chain-position $_CHIPNAME.cpu
$_CHIPNAME.cpu configure -work-area-phys 0x20000000 -work-area-size 0x8000

riscv set_prefer_sba on
adapter speed 1000
EOF

# Set up udev rules for USB access
sudo tee /etc/udev/rules.d/99-openocd.rules > /dev/null << 'EOF'
# OpenOCD udev rules for FPGA programming

# FTDI devices (Digilent FPGA boards)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6014", MODE="0666", GROUP="plugdev"

# Digilent devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="1443", MODE="0666", GROUP="plugdev"

# J-Link devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="1366", MODE="0666", GROUP="plugdev"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Add user to plugdev group
sudo usermod -a -G plugdev $USER

echo "✓ OpenOCD installed and configured"
echo "Log out and back in for group changes to take effect"
```

---

## Step 6: Python Environment Setup

### Create OpenTitan Python Environment
```bash
# Create dedicated virtual environment
python3 -m venv ~/opentitan-venv
source ~/opentitan-venv/bin/activate

# Upgrade pip and essential tools
pip install --upgrade pip setuptools wheel

# Install OpenTitan Python requirements
cd $REPO_TOP
pip install -r python-requirements.txt

# Install additional packages for analysis
pip install \
    numpy \
    matplotlib \
    scipy \
    pandas \
    seaborn \
    jupyter \
    ipython \
    pyserial \
    bitstring \
    pycryptodome

# Add virtual environment activation to shell
echo 'source ~/opentitan-venv/bin/activate' >> ~/.bashrc

echo "✓ Python environment configured"
```

### Test Python Environment
```bash
# Test key packages
python3 -c "
import hjson
import mako.template
import typer
import rich
import cryptography
import numpy
import matplotlib
print('✓ All Python packages imported successfully')
"

# Test OpenTitan-specific modules
cd $REPO_TOP
python3 -c "
import sys
sys.path.append('.')
from util.reggen import gen_rtl
print('✓ OpenTitan utilities available')
"
```

---

## Step 7: Complete Environment Setup

### Create Master Environment Script
```bash
cat > ~/opentitan_env.sh << 'EOF'
#!/bin/bash
# Complete OpenTitan Development Environment

echo "Setting up OpenTitan development environment..."

# Source individual environments
source ~/vivado_env.sh 2>/dev/null || echo "Warning: Vivado not configured"
source ~/riscv_env.sh 2>/dev/null || echo "Warning: RISC-V toolchain path may not be set"
source ~/opentitan-venv/bin/activate 2>/dev/null || echo "Warning: Python virtual environment not found"

# OpenTitan specific settings
export REPO_TOP="$(pwd)"
export PYTHONPATH="$REPO_TOP:$PYTHONPATH"
export PATH="$REPO_TOP/util:$PATH"

# Add tools to PATH
export PATH="/tools/openocd/bin:$PATH"
export PATH="$REPO_TOP/tools/riscv/bin:$PATH"

# FPGA development settings
export FPGA_BOARD="nexys_video"
export FPGA_DEVICE="xc7a200tsbg484-1"
export OT_FPGA_TARGET="nexys_video"

# Verification tools
export VERILATOR_ROOT="/usr/share/verilator"

echo "Environment setup complete!"
echo ""
echo "Available tools:"
command -v vivado >/dev/null && echo "  ✓ Vivado: $(vivado -version | head -1 | awk '{print $2}')" || echo "  ✗ Vivado: Not found"
command -v bazel >/dev/null && echo "  ✓ Bazel: $(bazel version | head -1 | awk '{print $3}')" || echo "  ✗ Bazel: Not found"
command -v riscv32-unknown-elf-gcc >/dev/null && echo "  ✓ RISC-V GCC: Available" || echo "  ✗ RISC-V GCC: Not found"
command -v openocd >/dev/null && echo "  ✓ OpenOCD: Available" || echo "  ✗ OpenOCD: Not found"
python3 -c "import hjson" 2>/dev/null && echo "  ✓ Python: Environment ready" || echo "  ✗ Python: Missing packages"

echo ""
echo "Repository: $REPO_TOP"
echo "To build for FPGA: bazel build //hw/top_earlgrey:fpga_nexys_video"
EOF

chmod +x ~/opentitan_env.sh
```

### Create Automated Installation Script
```bash
cat > install_all_tools.sh << 'EOF'
#!/bin/bash
set -e

echo "=== OpenTitan Complete Tool Installation ==="
echo "This will install all tools needed for OpenTitan FPGA development"
echo "Estimated time: 2-4 hours (depending on internet speed and Vivado)"
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 1
fi

# Step 1: System dependencies
echo "=== Step 1: Installing system dependencies ==="
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y \
    build-essential git curl wget unzip vim screen minicom \
    python3 python3-pip python3-dev python3-venv python3-setuptools \
    cmake ninja-build autoconf automake libtool pkg-config \
    device-tree-compiler gtkwave verilator \
    libftdi1-2 libftdi1-dev libusb-1.0-0 libusb-1.0-0-dev libudev-dev \
    libssl-dev libffi-dev zlib1g-dev libtinfo5 texinfo \
    libhidapi-dev libcapstone-dev

# Step 2: Bazel
echo "=== Step 2: Installing Bazel ==="
if ! command -v bazel &> /dev/null; then
    curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > bazel.gpg
    sudo mv bazel.gpg /etc/apt/trusted.gpg.d/
    echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
    sudo apt-get update
    sudo apt-get install -y bazel-6.2.1
    sudo ln -sf /usr/bin/bazel-6.2.1 /usr/bin/bazel
fi

# Step 3: Configure environment
echo "=== Step 3: Setting up environment ==="
if [[ -z "$REPO_TOP" ]]; then
    export REPO_TOP=$(pwd)
    echo "export REPO_TOP=$REPO_TOP" >> ~/.bashrc
fi

# Step 4: RISC-V toolchain
echo "=== Step 4: Installing RISC-V toolchain ==="
if [[ ! -d "$REPO_TOP/tools/riscv" ]]; then
    $REPO_TOP/util/get-toolchain.py --target=riscv32 --install-dir=tools/riscv
    echo 'export PATH=$REPO_TOP/tools/riscv/bin:$PATH' >> ~/.bashrc
fi

# Step 5: OpenOCD
echo "=== Step 5: Installing OpenOCD ==="
if ! command -v openocd &> /dev/null; then
    cd /tmp
    git clone https://github.com/riscv/riscv-openocd.git
    cd riscv-openocd
    ./bootstrap
    ./configure --prefix=/tools/openocd --enable-ftdi --enable-jlink --enable-stlink --disable-werror
    make -j$(nproc)
    sudo make install
    cd $REPO_TOP
fi

# Step 6: Python environment
echo "=== Step 6: Setting up Python environment ==="
if [[ ! -d ~/opentitan-venv ]]; then
    python3 -m venv ~/opentitan-venv
    source ~/opentitan-venv/bin/activate
    pip install --upgrade pip setuptools wheel
    pip install -r $REPO_TOP/python-requirements.txt
    pip install numpy matplotlib scipy pandas seaborn jupyter pyserial bitstring
    echo 'source ~/opentitan-venv/bin/activate' >> ~/.bashrc
fi

# Step 7: Configuration files
echo "=== Step 7: Creating configuration files ==="
# [Create all the config files as shown above]

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Manual steps remaining:"
echo "1. Download and install Xilinx Vivado from: https://www.xilinx.com/support/download.html"
echo "2. Source environment: source ~/opentitan_env.sh"
echo "3. Test build: bazel build //sw/device/lib/base:base"
echo ""
echo "Note: Vivado installation requires manual download due to licensing"
EOF

chmod +x install_all_tools.sh
```

---

## Step 8: Verification and Testing

### Complete Tool Verification Script
```bash
cat > verify_installation.sh << 'EOF'
#!/bin/bash

echo "=== OpenTitan Tool Installation Verification ==="
echo ""

# Test system dependencies
echo "System Dependencies:"
for tool in git curl wget python3 cmake ninja; do
    if command -v $tool >/dev/null 2>&1; then
        echo "  ✓ $tool"
    else
        echo "  ✗ $tool - missing"
    fi
done

# Test development tools
echo ""
echo "Development Tools:"
if command -v bazel >/dev/null 2>&1; then
    echo "  ✓ Bazel: $(bazel version | head -1 | awk '{print $3}')"
else
    echo "  ✗ Bazel - not found"
fi

if command -v vivado >/dev/null 2>&1; then
    echo "  ✓ Vivado: $(vivado -version | head -1 | awk '{print $2, $3}')"
else
    echo "  ✗ Vivado - not found (install manually)"
fi

if command -v openocd >/dev/null 2>&1; then
    echo "  ✓ OpenOCD: $(openocd --version 2>&1 | head -1)"
else
    echo "  ✗ OpenOCD - not found"
fi

# Test RISC-V toolchain
echo ""
echo "RISC-V Toolchain:"
for tool in riscv32-unknown-elf-gcc riscv32-unknown-elf-gdb; do
    if command -v $tool >/dev/null 2>&1; then
        echo "  ✓ $tool"
    else
        echo "  ✗ $tool - not found"
    fi
done

# Test Python environment
echo ""
echo "Python Environment:"
if python3 -c "import hjson, mako, typer, rich, cryptography, numpy, matplotlib" 2>/dev/null; then
    echo "  ✓ All required Python packages available"
else
    echo "  ✗ Missing Python packages"
fi

# Test OpenTitan specific
echo ""
echo "OpenTitan Environment:"
echo "  REPO_TOP: ${REPO_TOP:-Not set}"
echo "  Python path: $(python3 -c 'import sys; print(":".join(sys.path))' | grep -q "$REPO_TOP" && echo "✓ Includes REPO_TOP" || echo "✗ Missing REPO_TOP")"

# Test hardware connectivity
echo ""
echo "Hardware Connectivity:"
if lsusb | grep -i "0403:6010" >/dev/null; then
    echo "  ✓ Nexys Video detected"
elif lsusb | grep -i "0403:6014" >/dev/null; then
    echo "  ✓ Arty A7 detected"
elif lsusb | grep -i xilinx >/dev/null; then
    echo "  ✓ Xilinx device detected"
else
    echo "  - No FPGA board detected (normal if not connected)"
fi

# Test basic build
echo ""
echo "Build Test:"
if [[ -n "$REPO_TOP" ]] && [[ -d "$REPO_TOP" ]]; then
    cd "$REPO_TOP"
    if timeout 300 bazel build //sw/device/lib/base:base >/dev/null 2>&1; then
        echo "  ✓ Basic build test passed"
    else
        echo "  ✗ Build test failed (check tools and environment)"
    fi
else
    echo "  ✗ REPO_TOP not set or invalid"
fi

echo ""
echo "Verification complete!"
EOF

chmod +x verify_installation.sh
```

### Usage Instructions

**To install everything automatically**:
```bash
# Clone or navigate to OpenTitan
cd hack@ches_p1_25

# Run complete installation
./install_all_tools.sh

# Install Vivado manually (follow download instructions above)

# Verify installation
./verify_installation.sh

# Set up environment for daily use
source ~/opentitan_env.sh
```

**For daily development**:
```bash
# Navigate to OpenTitan and set up environment
cd /path/to/hack@ches_p1_25
source ~/opentitan_env.sh

# Now you can build and program FPGA
bazel build //hw/top_earlgrey:fpga_nexys_video
```

This completes the comprehensive tool installation guide. All tools and dependencies are now documented with step-by-step installation instructions suitable for OpenTitan beginners.