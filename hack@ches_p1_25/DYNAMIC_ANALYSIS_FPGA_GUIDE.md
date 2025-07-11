# Dynamic Analysis of OpenTitan on FPGA - Complete Guide

## Introduction: Static vs Dynamic Analysis

### What We Did (Static Analysis)
- **Static Analysis**: Examined source code without running it
- Like reading a car's blueprint to find design flaws
- Found 48 vulnerabilities by analyzing SystemVerilog files
- No actual hardware execution required

### What We'll Do Now (Dynamic Analysis)  
- **Dynamic Analysis**: Actually run OpenTitan on real hardware (FPGA)
- Like test-driving the car to see if the flaws actually cause crashes
- Verify our static analysis findings work in practice
- Discover runtime-only vulnerabilities that static analysis can't find

---

## Table of Contents
1. [Understanding FPGA vs ASIC](#understanding-fpga-vs-asic)
2. [Required Hardware and Software](#required-hardware-and-software)
3. [Environment Setup Process](#environment-setup-process)
4. [Building OpenTitan for FPGA](#building-opentitan-for-fpga)
5. [FPGA Programming and Deployment](#fpga-programming-and-deployment)
6. [Dynamic Testing Framework](#dynamic-testing-framework)
7. [Vulnerability Exploitation Testing](#vulnerability-exploitation-testing)
8. [Advanced Dynamic Analysis Techniques](#advanced-dynamic-analysis-techniques)

---

## Understanding FPGA vs ASIC

### What is an FPGA?
**FPGA** (Field-Programmable Gate Array) is like a "blank computer chip" that you can program to behave like any digital circuit.

**Think of it like:**
- **ASIC** (final chip) = A car built in a factory - fixed design, can't be changed
- **FPGA** = A modular car kit - you can reconfigure it into different vehicles

### Why Use FPGA for Testing?
1. **Prototype Testing**: Test chip design before expensive manufacturing
2. **Real Hardware Behavior**: Unlike software simulation, FPGA runs at hardware speeds
3. **Debug Access**: FPGA boards provide easy access to internal signals
4. **Iterative Development**: Can reprogram to test fixes quickly

---

## Required Hardware and Software

### Hardware Requirements

#### FPGA Development Board
**Recommended**: Xilinx Nexys Video (XC7A200T) or similar
- **Why this board**: OpenTitan officially supports Xilinx 7-series FPGAs
- **Cost**: ~$500-800 (educational discounts available)
- **Where to buy**: Digilent.com, Xilinx.com, or authorized distributors
- **Features needed**:
  - Sufficient logic elements (200K+ LUTs)
  - DDR memory interface
  - USB/UART connectivity
  - JTAG interface for debugging

#### Alternative Boards (if budget limited):
- **Digilent Arty A7-100T** (~$200) - smaller but sufficient for basic testing
- **Xilinx KC705 evaluation board** - more expensive but more capable
- **CW305 Artix FPGA Target** - specifically designed for security research

#### Additional Hardware:
```
Required Cables and Accessories:
├── USB-A to Micro-USB cable (for programming FPGA)
├── USB-A to USB-B cable (for UART communication)
├── JTAG debugger (Digilent HS2 or similar - ~$60)
├── Oscilloscope or logic analyzer (for advanced analysis - optional)
├── Breadboard and jumper wires (for external connections)
└── Power supply (usually included with FPGA board)
```

### Complete Software Installation Guide

#### Operating System Requirements
```bash
# Recommended: Ubuntu 20.04 LTS or 22.04 LTS
# Windows 10/11 also supported but Linux preferred for OpenTitan development
# Minimum requirements:
# - 16GB RAM (32GB recommended)
# - 100GB free disk space
# - Multi-core CPU (4+ cores recommended)
```

#### Step 1: System Dependencies Installation
```bash
# Update system packages
sudo apt-get update && sudo apt-get upgrade -y

# Install essential build tools
sudo apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    cmake \
    ninja-build \
    pkg-config \
    libssl-dev \
    libffi-dev \
    device-tree-compiler \
    screen \
    minicom \
    gtkwave \
    verilator

# Install additional development tools
sudo apt-get install -y \
    clang \
    clang-format \
    clang-tidy \
    lld \
    gcc-riscv64-unknown-elf \
    libc6-dev-i386

# Install Python packages for OpenTitan
pip3 install --user \
    wheel \
    setuptools \
    pyyaml \
    hjson \
    bitstring \
    cryptography \
    ecdsa \
    pyserial \
    numpy \
    matplotlib \
    scipy
```

#### Step 2: Xilinx Vivado Installation (Detailed)
```bash
# Create installation directory
sudo mkdir -p /tools/Xilinx
sudo chown $USER:$USER /tools/Xilinx

# Download Vivado WebPACK (free version)
# Go to: https://www.xilinx.com/support/download.html
# Download: "Vivado WebPACK 2023.1" (latest stable version)
# File size: ~35GB download, ~75GB installed

# Extract installer
cd ~/Downloads
tar -xvf Xilinx_Unified_2023.1_0507_1903.tar.gz
cd Xilinx_Unified_2023.1_0507_1903/

# Create installation config file
cat > install_config.txt << 'EOF'
#### Vivado WebPACK Installation Configuration ####
Edition=Vivado WebPACK
Destination=/tools/Xilinx
Modules=Vivado:1,Vitis:0,DocNav:1
InstallOptions=Acquire or Manage a License Key:0,Enable WebTalk for Vivado to send usage statistics to Xilinx:1
CreateProgramGroupShortcuts=0
ProgramGroupFolder=Xilinx Design Tools
CreateShortcutsForAllUsers=0
CreateDesktopShortcuts=0
CreateFileAssociation=0
LaunchVivado=0
EOF

# Run installer (graphical interface)
sudo ./xsetup --agree 3rdPartyEULA,XilinxEULA --batch Install --config install_config.txt

# Alternative: Interactive installation
# sudo ./xsetup
# Follow GUI prompts:
# 1. Select "Vivado"
# 2. Choose "Vivado WebPACK" (free)
# 3. Installation directory: /tools/Xilinx
# 4. Install takes 30-60 minutes
```

#### Step 3: Vivado Environment Setup
```bash
# Create Vivado environment script
cat > ~/vivado_setup.sh << 'EOF'
#!/bin/bash
# Vivado Environment Setup Script

# Vivado installation path
export VIVADO_ROOT="/tools/Xilinx/Vivado/2023.1"

# Check if Vivado is installed
if [ -d "$VIVADO_ROOT" ]; then
    # Source Vivado settings
    source $VIVADO_ROOT/settings64.sh
    
    # Add Vivado to PATH
    export PATH="$VIVADO_ROOT/bin:$PATH"
    
    # Set license (for WebPACK, no license needed)
    export XILINXD_LICENSE_FILE="$VIVADO_ROOT/data/xilinx.lic"
    
    echo "Vivado environment configured successfully"
    echo "Vivado version: $(vivado -version | head -1)"
else
    echo "ERROR: Vivado not found at $VIVADO_ROOT"
    echo "Please check installation path"
fi
EOF

chmod +x ~/vivado_setup.sh

# Test Vivado installation
source ~/vivado_setup.sh
vivado -version
```

#### Step 4: RISC-V Toolchain Installation
```bash
# Download precompiled RISC-V toolchain
cd /tmp
wget https://github.com/lowRISC/lowrisc-toolchains/releases/download/20220210-1/lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz

# Extract toolchain
sudo mkdir -p /tools/riscv
sudo tar -xf lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz -C /tools/riscv --strip-components=1

# Alternative: Build from source (takes 2-3 hours)
# git clone https://github.com/riscv/riscv-gnu-toolchain
# cd riscv-gnu-toolchain
# ./configure --prefix=/tools/riscv --with-arch=rv32imc --with-abi=ilp32
# make

# Set up RISC-V environment
cat > ~/riscv_setup.sh << 'EOF'
#!/bin/bash
# RISC-V Toolchain Environment Setup

export RISCV_ROOT="/tools/riscv"
export PATH="$RISCV_ROOT/bin:$PATH"

# Verify installation
if command -v riscv32-unknown-elf-gcc &> /dev/null; then
    echo "RISC-V toolchain configured successfully"
    echo "GCC version: $(riscv32-unknown-elf-gcc --version | head -1)"
else
    echo "ERROR: RISC-V toolchain not found"
fi
EOF

chmod +x ~/riscv_setup.sh
source ~/riscv_setup.sh
```

#### Step 5: Bazel Build System Installation
```bash
# Install Bazel (OpenTitan's build system)
# Method 1: Using Bazelisk (recommended)
curl -Lo bazelisk https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x bazelisk
sudo mv bazelisk /usr/local/bin/bazel

# Method 2: Direct Bazel installation
# wget https://github.com/bazelbuild/bazel/releases/download/6.4.0/bazel-6.4.0-installer-linux-x86_64.sh
# chmod +x bazel-6.4.0-installer-linux-x86_64.sh
# sudo ./bazel-6.4.0-installer-linux-x86_64.sh

# Verify Bazel installation
bazel version

# Configure Bazel for OpenTitan
cat > ~/.bazelrc << 'EOF'
# OpenTitan Bazel Configuration
build --incompatible_enable_cc_toolchain_resolution
build --action_env=PATH
build --host_action_env=PATH
test --test_output=errors
build --symlink_prefix=bazel-
EOF
```

#### Step 6: OpenOCD Installation (for JTAG debugging)
```bash
# Install dependencies for OpenOCD
sudo apt-get install -y \
    libtool \
    libftdi-dev \
    libusb-1.0-0-dev \
    autoconf \
    automake \
    texinfo

# Clone and build OpenOCD with RISC-V support
cd /tmp
git clone https://github.com/riscv/riscv-openocd.git
cd riscv-openocd

# Configure and build
./bootstrap
./configure --prefix=/tools/openocd \
            --enable-ftdi \
            --enable-usb_blaster_2 \
            --enable-jlink \
            --disable-werror

make -j$(nproc)
sudo make install

# Set up OpenOCD environment
cat > ~/openocd_setup.sh << 'EOF'
#!/bin/bash
# OpenOCD Environment Setup

export OPENOCD_ROOT="/tools/openocd"
export PATH="$OPENOCD_ROOT/bin:$PATH"

# Add udev rules for JTAG adapters
if [ ! -f "/etc/udev/rules.d/99-openocd.rules" ]; then
    echo "Setting up udev rules for JTAG adapters..."
    sudo tee /etc/udev/rules.d/99-openocd.rules > /dev/null << 'RULES'
# FTDI devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6014", MODE="0666"

# Digilent devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="1443", MODE="0666"
RULES
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi

echo "OpenOCD environment configured"
EOF

chmod +x ~/openocd_setup.sh
source ~/openocd_setup.sh
```

#### Step 7: Complete Environment Setup Script
```bash
# Create master environment setup script
cat > ~/opentitan_complete_setup.sh << 'EOF'
#!/bin/bash
# Complete OpenTitan Development Environment Setup

echo "Setting up OpenTitan development environment..."

# Source individual tool setups
source ~/vivado_setup.sh
source ~/riscv_setup.sh  
source ~/openocd_setup.sh

# OpenTitan specific environment
export REPO_TOP="$(pwd)"
export PYTHONPATH="$REPO_TOP:$PYTHONPATH"

# Add OpenTitan utilities to PATH
export PATH="$REPO_TOP/util:$PATH"

# FPGA-specific settings
export OT_FPGA_BOARD="nexys_video"
export OT_FPGA_DEVICE="xc7a200tsbg484-1"

# Verification tools
export PATH="/tools/verilator/bin:$PATH"

echo "Environment setup complete!"
echo "Available tools:"
echo "  - Vivado: $(which vivado)"
echo "  - RISC-V GCC: $(which riscv32-unknown-elf-gcc)"
echo "  - Bazel: $(which bazel)"
echo "  - OpenOCD: $(which openocd)"
echo "  - Python: $(which python3)"

# Test basic functionality
echo ""
echo "Running basic tests..."
python3 -c "import hjson; print('✓ HJSON available')"
bazel version | head -1
riscv32-unknown-elf-gcc --version | head -1

echo ""
echo "Setup verification complete!"
echo "You can now proceed with OpenTitan FPGA development."
EOF

chmod +x ~/opentitan_complete_setup.sh
```

---

## Environment Setup Process

### Step 0: Complete Installation Script (Run This First)
```bash
# Create and run the complete installation script
# This will install everything automatically

cat > ~/install_opentitan_tools.sh << 'EOF'
#!/bin/bash
# Complete OpenTitan FPGA Development Environment Installer
# Run this script to install all required tools

set -e  # Exit on any error

echo "=================================================="
echo "OpenTitan FPGA Development Environment Installer"
echo "=================================================="
echo "This script will install:"
echo "  - System dependencies"
echo "  - Xilinx Vivado WebPACK"
echo "  - RISC-V toolchain"
echo "  - Bazel build system"
echo "  - OpenOCD debugger"
echo "  - Python packages"
echo ""
echo "Total installation time: 1-2 hours"
echo "Disk space required: ~100GB"
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 1
fi

echo "Starting installation..."

# Step 1: System dependencies
echo "==============================================="
echo "Step 1/6: Installing system dependencies..."
echo "==============================================="
sudo apt-get update && sudo apt-get upgrade -y

sudo apt-get install -y \
    build-essential git curl wget unzip python3 python3-pip python3-venv \
    python3-dev cmake ninja-build pkg-config libssl-dev libffi-dev \
    device-tree-compiler screen minicom gtkwave verilator clang \
    clang-format clang-tidy lld gcc-riscv64-unknown-elf libc6-dev-i386 \
    libtool libftdi-dev libusb-1.0-0-dev autoconf automake texinfo

# Install Python packages
pip3 install --user wheel setuptools pyyaml hjson bitstring cryptography \
    ecdsa pyserial numpy matplotlib scipy meson

echo "✓ System dependencies installed"

# Step 2: Create tools directory
echo "==============================================="
echo "Step 2/6: Setting up tool directories..."
echo "==============================================="
sudo mkdir -p /tools/{Xilinx,riscv,openocd}
sudo chown -R $USER:$USER /tools/

echo "✓ Tool directories created"

# Step 3: RISC-V Toolchain
echo "==============================================="
echo "Step 3/6: Installing RISC-V toolchain..."
echo "==============================================="
cd /tmp
wget -q https://github.com/lowRISC/lowrisc-toolchains/releases/download/20220210-1/lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz
tar -xf lowrisc-toolchain-gcc-rv32imcb-20220210-1.tar.xz -C /tools/riscv --strip-components=1

echo "✓ RISC-V toolchain installed"

# Step 4: Bazel
echo "==============================================="
echo "Step 4/6: Installing Bazel..."
echo "==============================================="
curl -Lo bazelisk https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64
chmod +x bazelisk
sudo mv bazelisk /usr/local/bin/bazel

# Configure Bazel
cat > ~/.bazelrc << 'BAZEL_EOF'
build --incompatible_enable_cc_toolchain_resolution
build --action_env=PATH
build --host_action_env=PATH
test --test_output=errors
build --symlink_prefix=bazel-
BAZEL_EOF

echo "✓ Bazel installed and configured"

# Step 5: OpenOCD
echo "==============================================="
echo "Step 5/6: Installing OpenOCD..."
echo "==============================================="
cd /tmp
git clone -q https://github.com/riscv/riscv-openocd.git
cd riscv-openocd
./bootstrap > /dev/null 2>&1
./configure --prefix=/tools/openocd --enable-ftdi --enable-usb_blaster_2 \
    --enable-jlink --disable-werror > /dev/null 2>&1
make -j$(nproc) > /dev/null 2>&1
make install > /dev/null 2>&1

# Set up udev rules
sudo tee /etc/udev/rules.d/99-openocd.rules > /dev/null << 'UDEV_EOF'
# FTDI devices
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6014", MODE="0666"
# Digilent devices  
SUBSYSTEM=="usb", ATTRS{idVendor}=="1443", MODE="0666"
UDEV_EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo "✓ OpenOCD installed"

# Step 6: Environment scripts
echo "==============================================="
echo "Step 6/6: Creating environment scripts..."
echo "==============================================="

# Individual tool scripts
cat > ~/riscv_setup.sh << 'RISCV_EOF'
#!/bin/bash
export RISCV_ROOT="/tools/riscv"
export PATH="$RISCV_ROOT/bin:$PATH"
RISCV_EOF

cat > ~/openocd_setup.sh << 'OPENOCD_EOF'
#!/bin/bash
export OPENOCD_ROOT="/tools/openocd"
export PATH="$OPENOCD_ROOT/bin:$PATH"
OPENOCD_EOF

# Master setup script (without Vivado for now)
cat > ~/opentitan_setup.sh << 'OT_EOF'
#!/bin/bash
# OpenTitan Development Environment (without Vivado)
source ~/riscv_setup.sh
source ~/openocd_setup.sh

export REPO_TOP="$(pwd)"
export PYTHONPATH="$REPO_TOP:$PYTHONPATH"
export PATH="$REPO_TOP/util:$PATH"

echo "OpenTitan environment ready (Vivado installation required separately)"
echo "Available tools:"
echo "  - RISC-V GCC: $(which riscv32-unknown-elf-gcc 2>/dev/null || echo 'Not found')"
echo "  - Bazel: $(which bazel 2>/dev/null || echo 'Not found')"
echo "  - OpenOCD: $(which openocd 2>/dev/null || echo 'Not found')"
OT_EOF

chmod +x ~/*_setup.sh

echo "✓ Environment scripts created"

echo ""
echo "=================================================="
echo "Installation Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Install Xilinx Vivado WebPACK manually (see guide below)"
echo "2. Run: source ~/opentitan_setup.sh"
echo "3. Test with: bazel version"
echo ""
echo "Vivado installation:"
echo "  1. Download from: https://www.xilinx.com/support/download.html"
echo "  2. Register for free account"
echo "  3. Download Vivado WebPACK 2023.1"
echo "  4. Run installer with GUI"
echo ""
EOF

chmod +x ~/install_opentitan_tools.sh

# Run the installer
echo "Running complete installation script..."
~/install_opentitan_tools.sh
```

### Step 1: Manual Vivado Installation (After Running Auto-Installer)
```bash
# After the auto-installer completes, install Vivado manually:

echo "=================================================="
echo "Manual Vivado Installation Guide"
echo "=================================================="
echo ""
echo "1. Go to: https://www.xilinx.com/support/download.html"
echo "2. Create free Xilinx account"
echo "3. Download: Vivado WebPACK 2023.1 (Linux installer)"
echo "4. File will be: Xilinx_Unified_2023.1_0507_1903.tar.gz (~35GB)"
echo ""
echo "After download completes, run these commands:"

cat > ~/install_vivado_manual.sh << 'EOF'
#!/bin/bash
# Manual Vivado Installation Script

echo "Extracting Vivado installer..."
cd ~/Downloads
tar -xf Xilinx_Unified_2023.1_*.tar.gz
cd Xilinx_Unified_2023.1_*/

echo "Starting Vivado installer..."
echo "In the GUI installer:"
echo "  1. Select 'Vivado'"
echo "  2. Choose 'Vivado WebPACK' (free version)"
echo "  3. Installation directory: /tools/Xilinx"
echo "  4. Accept license agreements"
echo "  5. Installation takes 30-60 minutes"

sudo ./xsetup

# After installation, create Vivado setup script
cat > ~/vivado_setup.sh << 'VIVADO_EOF'
#!/bin/bash
export VIVADO_ROOT="/tools/Xilinx/Vivado/2023.1"
if [ -d "$VIVADO_ROOT" ]; then
    source $VIVADO_ROOT/settings64.sh
    export PATH="$VIVADO_ROOT/bin:$PATH"
    echo "Vivado configured: $(vivado -version 2>/dev/null | head -1)"
else
    echo "ERROR: Vivado not found at $VIVADO_ROOT"
fi
VIVADO_EOF

chmod +x ~/vivado_setup.sh

# Update master setup script to include Vivado
cat > ~/opentitan_complete_setup.sh << 'COMPLETE_EOF'
#!/bin/bash
# Complete OpenTitan Development Environment
source ~/vivado_setup.sh
source ~/riscv_setup.sh
source ~/openocd_setup.sh

export REPO_TOP="$(pwd)"
export PYTHONPATH="$REPO_TOP:$PYTHONPATH"
export PATH="$REPO_TOP/util:$PATH"
export OT_FPGA_BOARD="nexys_video"

echo "Complete OpenTitan environment ready!"
echo "Tools available:"
echo "  - Vivado: $(which vivado 2>/dev/null || echo 'Not found')"
echo "  - RISC-V GCC: $(which riscv32-unknown-elf-gcc 2>/dev/null || echo 'Not found')"
echo "  - Bazel: $(which bazel 2>/dev/null || echo 'Not found')"  
echo "  - OpenOCD: $(which openocd 2>/dev/null || echo 'Not found')"
COMPLETE_EOF

chmod +x ~/opentitan_complete_setup.sh

echo "Vivado installation complete!"
echo "Run: source ~/opentitan_complete_setup.sh"
EOF

chmod +x ~/install_vivado_manual.sh
```

### Step 2: Verify Installation
```bash
# After all installations complete, verify everything works
source ~/opentitan_complete_setup.sh

# Test each tool
echo "Testing installations..."

echo "1. Bazel:"
bazel version

echo "2. RISC-V toolchain:"
riscv32-unknown-elf-gcc --version

echo "3. OpenOCD:"
openocd --version

echo "4. Vivado:"
vivado -version

echo "5. Python packages:"
python3 -c "import hjson, yaml, serial; print('✓ Python packages OK')"

echo "Installation verification complete!"
```

### Step 3: Navigate to OpenTitan and Set Environment
```bash
# Navigate to our OpenTitan directory
cd hack@ches_p1_25

# Set up environment for this session
source ~/opentitan_complete_setup.sh

# Verify OpenTitan environment is ready
echo "Repository root: $REPO_TOP"
echo "Python path: $PYTHONPATH"
echo "FPGA board: $OT_FPGA_BOARD"
```

### Step 2: Install FPGA-Specific Dependencies
```bash
# Install Python packages for FPGA development
pip3 install --user \
    pyyaml \
    hjson \
    bitstring \
    cryptography \
    ecdsa

# Install OpenTitan-specific tools
cd $REPO_TOP
./util/get-toolchain.py --target=all --install-dir=tools
```

### Step 3: Configure Vivado Environment
```bash
# Add Vivado to PATH (adjust path based on installation)
export VIVADO_PATH="/tools/Xilinx/Vivado/2021.1"
export PATH="$VIVADO_PATH/bin:$PATH"

# Verify installation
vivado -version
```

### Step 4: Set Up FPGA-Specific Environment Variables
```bash
# Create FPGA environment script
cat > fpga_env.sh << 'EOF'
#!/bin/bash
# FPGA Development Environment Setup

# Source OpenTitan environment first
source env.sh

# Vivado settings
export VIVADO_PATH="/tools/Xilinx/Vivado/2021.1"
export PATH="$VIVADO_PATH/bin:$PATH"

# FPGA board configuration
export FPGA_BOARD="nexys_video"  # or your specific board
export FPGA_DEVICE="xc7a200tsbg484-1"

# OpenTitan FPGA configuration
export OT_FPGA_TARGET="nexys_video"
export OT_FPGA_FREQUENCY="100000000"  # 100 MHz

echo "FPGA environment configured for $FPGA_BOARD"
EOF

chmod +x fpga_env.sh
source fpga_env.sh
```

---

## Building OpenTitan for FPGA

### Step 1: Configure Build for FPGA Target
```bash
# Source our FPGA environment
source fpga_env.sh

# Navigate to FPGA build directory
cd $REPO_TOP

# Generate FPGA configuration
./util/topgen.py -t hw/top_earlgrey/data/top_earlgrey.hjson \
                 -o hw/top_earlgrey/ \
                 --rnd_cnst_seed 4881560218204344518

# This creates the FPGA-specific hardware configuration
```

### Step 2: Build FPGA Bitstream
```bash
# Clean any previous builds
make -C hw/top_earlgrey clean

# Build the FPGA bitstream (this takes 30-60 minutes)
echo "Starting FPGA build - this will take significant time..."
make -C hw/top_earlgrey fpga_nexys_video

# The build process will:
# 1. Synthesize SystemVerilog to netlist
# 2. Place and route the design
# 3. Generate timing reports
# 4. Create .bit file for programming FPGA
```

**What happens during build:**
```
Build Process Steps:
├── Synthesis: Convert SystemVerilog to gate-level netlist
├── Implementation: 
│   ├── Opt_design: Optimize logic 
│   ├── Place_design: Position components on FPGA
│   ├── Route_design: Connect components with wires
│   └── Write_bitstream: Generate programming file
└── Output: build/lowrisc_systems_top_earlgrey_nexys_video_0.1/synth-vivado/top_earlgrey_nexys_video.bit
```

### Step 3: Build Test Software
```bash
# Build software that will run on our FPGA OpenTitan
cd $REPO_TOP

# Build test programs
make -C sw/device/tests hello_world_fpga
make -C sw/device/tests uart_smoketest_fpga

# Build our custom vulnerability test programs
make -C sw/device/tests debug_test_fpga
make -C sw/device/tests alert_test_fpga
```

---

## FPGA Programming and Deployment

### Step 1: Connect FPGA Board
```bash
# Physical connections:
# 1. Connect FPGA board to computer via USB
# 2. Power on the FPGA board
# 3. Verify connection

# Check if board is detected
lsusb | grep -i xilinx
# Should show: Bus XXX Device XXX: ID 0403:6010 Future Technology Devices International, Ltd
```

### Step 2: Program FPGA with OpenTitan
```bash
# Program the FPGA with our OpenTitan bitstream
cd $REPO_TOP

# Use Vivado to program FPGA
vivado -mode batch -source scripts/program_fpga.tcl \
       -tclargs build/lowrisc_systems_top_earlgrey_nexys_video_0.1/synth-vivado/top_earlgrey_nexys_video.bit

# Alternative using OpenOCD (if available)
openocd -f interface/ftdi/digilent_nexys_video.cfg \
        -f target/xilinx_fpga.cfg \
        -c "init; pld load 0 top_earlgrey_nexys_video.bit; exit"
```

### Step 3: Verify FPGA Programming Success
```bash
# Check FPGA status LEDs (board-specific)
# For Nexys Video:
# - Power LED should be solid
# - DONE LED should be lit (indicates successful programming)
# - User LEDs may show activity patterns

# Test basic UART connectivity
screen /dev/ttyUSB1 115200
# Should show OpenTitan boot messages
```

### Step 4: Load Test Software
```bash
# Use JTAG to load our test programs
openocd -f interface/ftdi/digilent_nexys_video.cfg \
        -f target/riscv.cfg \
        -c "init; halt; load_image sw/device/tests/hello_world_fpga.elf; resume; exit"

# Verify program execution via UART
# Should see "Hello World from OpenTitan FPGA!" in terminal
```

---

## Dynamic Testing Framework

### Step 1: Create Vulnerability Test Suite
```bash
# Create dynamic test directory
mkdir -p tests/dynamic_analysis
cd tests/dynamic_analysis
```

Create test framework:
```c
// File: tests/dynamic_analysis/vulnerability_test_framework.c
#include <stdint.h>
#include <stdbool.h>
#include "sw/device/lib/base/mmio.h"
#include "sw/device/lib/dif/dif_uart.h"
#include "sw/device/lib/runtime/log.h"

// Debug module register addresses (from our static analysis)
#define DEBUG_BASE_ADDR 0x41200000
#define DM_CONTROL_REG (DEBUG_BASE_ADDR + 0x10)
#define DM_COMMAND_REG (DEBUG_BASE_ADDR + 0x17)

// Alert handler register addresses
#define ALERT_HANDLER_BASE 0x411B0000
#define ALERT_PING_TIMER_REG (ALERT_HANDLER_BASE + 0x200)

typedef struct {
    const char* test_name;
    bool (*test_function)(void);
    uint32_t expected_result;
} vulnerability_test_t;

// Test our Bug #1: Debug Access Control Bypass
bool test_debug_access_bypass(void) {
    LOG_INFO("Testing Debug Access Control Bypass...");
    
    // Attempt to write to debug control register without authentication
    uint32_t malicious_control = 0x80000001;  // dmactive=1, haltreq=1
    
    // This should fail in a secure system, but our static analysis
    // found it doesn't check privileges
    mmio_region_t debug_region = mmio_region_from_addr(DEBUG_BASE_ADDR);
    
    // Attempt unauthorized write
    mmio_region_write32(debug_region, DM_CONTROL_REG - DEBUG_BASE_ADDR, malicious_control);
    
    // Read back to verify if write succeeded
    uint32_t read_value = mmio_region_read32(debug_region, DM_CONTROL_REG - DEBUG_BASE_ADDR);
    
    if (read_value == malicious_control) {
        LOG_ERROR("VULNERABILITY CONFIRMED: Debug access control bypassed!");
        return true;  // Vulnerability exists
    } else {
        LOG_INFO("Debug access properly protected");
        return false;  // Vulnerability fixed/not present
    }
}

// Test our Bug #3: Alert Handler Ping Bypass
bool test_alert_ping_bypass(void) {
    LOG_INFO("Testing Alert Handler Ping Bypass...");
    
    mmio_region_t alert_region = mmio_region_from_addr(ALERT_HANDLER_BASE);
    
    // Monitor ping requests and responses
    uint32_t ping_req_initial = mmio_region_read32(alert_region, 0x100);
    
    // Inject spurious ping response (our static analysis found this bypasses detection)
    mmio_region_write32(alert_region, 0x104, 0x1);  // Fake ping response
    
    // Wait and check if spurious detection triggered
    for (int i = 0; i < 1000; i++) {
        uint32_t spurious_status = mmio_region_read32(alert_region, 0x108);
        if (spurious_status & 0x1) {
            LOG_INFO("Spurious ping properly detected");
            return false;
        }
    }
    
    LOG_ERROR("VULNERABILITY CONFIRMED: Spurious ping not detected!");
    return true;
}

// Main test execution
int main(void) {
    LOG_INFO("Starting OpenTitan Dynamic Vulnerability Analysis");
    
    vulnerability_test_t tests[] = {
        {"Debug Access Control Bypass", test_debug_access_bypass, 1},
        {"Alert Ping Bypass", test_alert_ping_bypass, 1},
        // Add more tests here
    };
    
    int passed = 0;
    int total = sizeof(tests) / sizeof(tests[0]);
    
    for (int i = 0; i < total; i++) {
        LOG_INFO("Running test: %s", tests[i].test_name);
        bool result = tests[i].test_function();
        
        if (result == tests[i].expected_result) {
            LOG_INFO("✓ Test PASSED");
            passed++;
        } else {
            LOG_ERROR("✗ Test FAILED");
        }
    }
    
    LOG_INFO("Dynamic Analysis Complete: %d/%d tests passed", passed, total);
    return 0;
}
```

### Step 2: Build and Deploy Dynamic Tests
```bash
# Build our vulnerability test suite
cd $REPO_TOP
make -C tests/dynamic_analysis vulnerability_test_framework_fpga

# Deploy to FPGA
openocd -f interface/ftdi/digilent_nexys_video.cfg \
        -f target/riscv.cfg \
        -c "init; halt; load_image tests/dynamic_analysis/vulnerability_test_framework.elf; resume; exit"
```

---

## Vulnerability Exploitation Testing

### Step 1: Debug Access Control Bypass (Dynamic Testing)

Create JTAG exploit script:
```bash
# File: tests/dynamic_analysis/debug_exploit.tcl
# OpenOCD script to test debug vulnerability

proc test_debug_bypass {} {
    echo "=== Testing Debug Access Control Bypass ==="
    
    # Connect to debug module without authentication
    init
    
    # Attempt to halt CPU (should require privileges)
    echo "Attempting unauthorized CPU halt..."
    halt
    
    # Check if halt succeeded
    set cpu_state [reg pc]
    if {$cpu_state != ""} {
        echo "VULNERABILITY CONFIRMED: CPU halted without authorization!"
        echo "Current PC: $cpu_state"
        
        # Try to read memory (should also require privileges)
        set memory_data [read_memory 0x20000000 32 4]
        echo "Memory read result: $memory_data"
        
        # Resume CPU
        resume
        return 1
    } else {
        echo "Debug access properly protected"
        return 0
    }
}

# Execute test
test_debug_bypass
exit
```

Run the exploit test:
```bash
# Execute our debug exploit test
openocd -f interface/ftdi/digilent_nexys_video.cfg \
        -f target/riscv.cfg \
        -f tests/dynamic_analysis/debug_exploit.tcl
```

### Step 2: Alert Handler Timing Analysis

Create timing measurement script:
```python
#!/usr/bin/env python3
# File: tests/dynamic_analysis/timing_analysis.py
"""
Dynamic timing analysis to verify LFSR predictability
"""

import serial
import time
import numpy as np
import matplotlib.pyplot as plt

def analyze_alert_timing():
    """Monitor alert handler ping timing for predictability"""
    
    # Connect to FPGA UART
    ser = serial.Serial('/dev/ttyUSB1', 115200, timeout=1)
    
    ping_intervals = []
    last_ping_time = time.time()
    
    print("Monitoring alert handler ping timing...")
    print("Looking for predictable patterns...")
    
    try:
        for i in range(1000):  # Collect 1000 samples
            line = ser.readline().decode('utf-8').strip()
            
            if 'PING_ALERT' in line:
                current_time = time.time()
                interval = current_time - last_ping_time
                ping_intervals.append(interval)
                last_ping_time = current_time
                
                print(f"Ping {len(ping_intervals)}: {interval:.6f}s")
                
                # Check for obvious patterns every 100 samples
                if len(ping_intervals) >= 100 and len(ping_intervals) % 100 == 0:
                    analyze_predictability(ping_intervals)
    
    except KeyboardInterrupt:
        print("Analysis interrupted by user")
    
    finally:
        ser.close()
        
    # Final analysis
    if len(ping_intervals) > 10:
        plot_timing_analysis(ping_intervals)
        return analyze_predictability(ping_intervals)
    
    return False

def analyze_predictability(intervals):
    """Analyze timing intervals for predictability"""
    
    if len(intervals) < 10:
        return False
    
    # Calculate statistics
    mean_interval = np.mean(intervals)
    std_interval = np.std(intervals)
    coefficient_of_variation = std_interval / mean_interval
    
    print(f"\nTiming Analysis Results:")
    print(f"Mean interval: {mean_interval:.6f}s")
    print(f"Standard deviation: {std_interval:.6f}s")
    print(f"Coefficient of variation: {coefficient_of_variation:.6f}")
    
    # Check for periodicity (sign of predictable LFSR)
    fft = np.fft.fft(intervals)
    frequencies = np.fft.fftfreq(len(intervals))
    
    # Find dominant frequencies
    magnitude = np.abs(fft)
    dominant_freq_idx = np.argmax(magnitude[1:]) + 1  # Skip DC component
    dominant_frequency = frequencies[dominant_freq_idx]
    
    print(f"Dominant frequency component: {dominant_frequency:.6f}")
    
    # Predictability indicators
    if coefficient_of_variation < 0.1:  # Very low variation
        print("WARNING: Timing appears highly predictable!")
        return True
    elif dominant_frequency > 0.1:  # Strong periodic component
        print("WARNING: Strong periodic pattern detected!")
        return True
    else:
        print("Timing appears sufficiently random")
        return False

def plot_timing_analysis(intervals):
    """Create visualizations of timing data"""
    
    plt.figure(figsize=(12, 8))
    
    # Time series plot
    plt.subplot(2, 2, 1)
    plt.plot(intervals)
    plt.title('Ping Timing Intervals')
    plt.xlabel('Sample Number')
    plt.ylabel('Interval (seconds)')
    
    # Histogram
    plt.subplot(2, 2, 2)
    plt.hist(intervals, bins=50, alpha=0.7)
    plt.title('Interval Distribution')
    plt.xlabel('Interval (seconds)')
    plt.ylabel('Frequency')
    
    # Autocorrelation
    plt.subplot(2, 2, 3)
    autocorr = np.correlate(intervals, intervals, mode='full')
    autocorr = autocorr[autocorr.size // 2:]
    plt.plot(autocorr[:min(100, len(autocorr))])
    plt.title('Autocorrelation')
    plt.xlabel('Lag')
    plt.ylabel('Correlation')
    
    # FFT
    plt.subplot(2, 2, 4)
    fft = np.fft.fft(intervals)
    frequencies = np.fft.fftfreq(len(intervals))
    plt.plot(frequencies[:len(frequencies)//2], np.abs(fft[:len(fft)//2]))
    plt.title('Frequency Spectrum')
    plt.xlabel('Frequency')
    plt.ylabel('Magnitude')
    
    plt.tight_layout()
    plt.savefig('timing_analysis.png')
    print("Timing analysis plot saved as 'timing_analysis.png'")

if __name__ == "__main__":
    predictable = analyze_alert_timing()
    
    if predictable:
        print("\nVULNERABILITY CONFIRMED: Alert timing is predictable!")
        print("This confirms our static analysis finding.")
    else:
        print("\nAlert timing appears random - vulnerability may be fixed.")
```

---

## Advanced Dynamic Analysis Techniques

### Step 1: Power Analysis for Side-Channel Detection
```bash
# Set up power analysis (requires oscilloscope or power measurement setup)
# This can reveal additional vulnerabilities not found in static analysis

# Install power analysis tools
pip3 install --user \
    scipy \
    matplotlib \
    numpy \
    pycryptodome

# Create power measurement script
cat > tests/dynamic_analysis/power_analysis.py << 'EOF'
#!/usr/bin/env python3
"""
Simple power analysis to detect cryptographic operations
and potential side-channel vulnerabilities
"""

import numpy as np
import matplotlib.pyplot as plt
import time

def capture_power_traces():
    """Capture power consumption during crypto operations"""
    
    print("Setting up power analysis...")
    print("Note: This requires external power measurement equipment")
    
    # Simulate power measurement (replace with real measurement code)
    # In practice, you'd interface with oscilloscope or power monitor
    
    traces = []
    
    for operation in ['aes_encrypt', 'rsa_sign', 'ecdsa_sign']:
        print(f"Capturing power trace for {operation}...")
        
        # Trigger cryptographic operation on FPGA
        trigger_crypto_operation(operation)
        
        # Capture power consumption
        # trace = capture_from_oscilloscope()  # Real implementation
        trace = simulate_power_trace(operation)  # Simulation for this example
        
        traces.append({
            'operation': operation,
            'trace': trace,
            'timestamp': time.time()
        })
    
    return traces

def simulate_power_trace(operation):
    """Simulate power trace for demonstration"""
    base_power = 100  # mW baseline
    samples = 1000
    
    # Different operations have different power signatures
    if operation == 'aes_encrypt':
        # AES has regular pattern due to rounds
        trace = base_power + 20 * np.sin(np.linspace(0, 16*2*np.pi, samples))
    elif operation == 'rsa_sign':
        # RSA has irregular pattern due to square-and-multiply
        trace = base_power + 30 * np.random.random(samples)
    else:
        # ECDSA has point multiplication pattern
        trace = base_power + 15 * np.sin(np.linspace(0, 8*2*np.pi, samples))
    
    # Add noise
    trace += 5 * np.random.normal(0, 1, samples)
    
    return trace

def trigger_crypto_operation(operation):
    """Trigger cryptographic operation on FPGA"""
    # Send command to FPGA to start specific crypto operation
    # This would be implemented based on your test harness
    print(f"Triggering {operation} on FPGA...")
    time.sleep(0.1)  # Simulate operation time

def analyze_power_traces(traces):
    """Analyze power traces for side-channel vulnerabilities"""
    
    plt.figure(figsize=(15, 10))
    
    for i, trace_data in enumerate(traces):
        plt.subplot(len(traces), 1, i+1)
        plt.plot(trace_data['trace'])
        plt.title(f"Power Trace: {trace_data['operation']}")
        plt.ylabel('Power (mW)')
        
        # Look for patterns that might leak information
        fft = np.fft.fft(trace_data['trace'])
        dominant_freq = np.argmax(np.abs(fft[1:len(fft)//2])) + 1
        
        if np.abs(fft[dominant_freq]) > np.mean(np.abs(fft)) * 3:
            print(f"WARNING: Strong periodic pattern in {trace_data['operation']}")
            print("This may indicate side-channel vulnerability!")
    
    plt.xlabel('Time Sample')
    plt.tight_layout()
    plt.savefig('power_analysis.png')
    print("Power analysis saved as 'power_analysis.png'")

if __name__ == "__main__":
    traces = capture_power_traces()
    analyze_power_traces(traces)
EOF
```

### Step 2: Fault Injection Testing
```bash
# Create fault injection test framework
cat > tests/dynamic_analysis/fault_injection.py << 'EOF'
#!/usr/bin/env python3
"""
Fault injection testing to find vulnerabilities that only appear
under adverse conditions (voltage glitching, clock manipulation, etc.)
"""

import time
import serial

class FaultInjector:
    def __init__(self, uart_port='/dev/ttyUSB1'):
        self.uart = serial.Serial(uart_port, 115200, timeout=1)
        
    def inject_clock_glitch(self, duration_us=10):
        """Simulate clock glitch injection"""
        print(f"Injecting clock glitch ({duration_us}µs)...")
        
        # In real setup, this would control external glitch hardware
        # For simulation, we send a special command to FPGA test harness
        self.uart.write(b'GLITCH_CLOCK\n')
        
        # Monitor response
        response = self.uart.readline().decode('utf-8').strip()
        return 'FAULT_DETECTED' in response
    
    def inject_voltage_drop(self, voltage_reduction=0.1):
        """Simulate voltage fault injection"""
        print(f"Injecting voltage drop (-{voltage_reduction}V)...")
        
        # Send voltage manipulation command
        cmd = f'GLITCH_VOLTAGE {voltage_reduction}\n'.encode()
        self.uart.write(cmd)
        
        # Check for fault effects
        response = self.uart.readline().decode('utf-8').strip()
        return 'FAULT_DETECTED' in response
    
    def test_secure_boot_bypass(self):
        """Test if fault injection can bypass secure boot"""
        print("Testing secure boot fault injection...")
        
        # Reset the system
        self.uart.write(b'RESET_SYSTEM\n')
        time.sleep(1)
        
        # Wait for secure boot to start
        time.sleep(0.5)
        
        # Inject fault during signature verification
        fault_occurred = self.inject_clock_glitch(duration_us=50)
        
        # Check if boot continues with invalid signature
        time.sleep(2)
        self.uart.write(b'GET_BOOT_STATUS\n')
        response = self.uart.readline().decode('utf-8').strip()
        
        if 'BOOT_SUCCESS' in response and fault_occurred:
            print("VULNERABILITY: Secure boot bypassed with fault injection!")
            return True
        else:
            print("Secure boot properly protected against faults")
            return False
    
    def test_crypto_fault_attack(self):
        """Test cryptographic operations under fault injection"""
        print("Testing cryptographic fault resistance...")
        
        # Start AES encryption
        self.uart.write(b'START_AES_ENCRYPT\n')
        time.sleep(0.1)
        
        # Inject fault during encryption
        fault_occurred = self.inject_voltage_drop(0.2)
        
        # Get encryption result
        self.uart.write(b'GET_AES_RESULT\n')
        result = self.uart.readline().decode('utf-8').strip()
        
        if fault_occurred and 'ERROR' not in result:
            print("WARNING: Crypto operation completed despite fault!")
            print("This may allow differential fault analysis attacks")
            return True
        else:
            print("Crypto operation properly protected")
            return False

def run_fault_injection_tests():
    """Run comprehensive fault injection test suite"""
    injector = FaultInjector()
    
    tests = [
        ('Secure Boot Bypass', injector.test_secure_boot_bypass),
        ('Crypto Fault Attack', injector.test_crypto_fault_attack),
    ]
    
    vulnerabilities_found = 0
    
    for test_name, test_func in tests:
        print(f"\n=== {test_name} ===")
        if test_func():
            vulnerabilities_found += 1
    
    print(f"\nFault injection testing complete.")
    print(f"Vulnerabilities found: {vulnerabilities_found}/{len(tests)}")
    
    return vulnerabilities_found

if __name__ == "__main__":
    run_fault_injection_tests()
EOF
```

---

## Troubleshooting Guide

### Common Installation Issues

#### Vivado Installation Problems
```bash
# Issue 1: "No space left on device" during Vivado installation
# Solution: Check disk space and clean up
df -h /tools/Xilinx
sudo apt-get clean
sudo apt-get autoremove

# Issue 2: Vivado license issues
# Solution: WebPACK doesn't need license, but ensure proper setup
export XILINXD_LICENSE_FILE="/tools/Xilinx/Vivado/2023.1/data/xilinx.lic"

# Issue 3: GUI installer won't start
# Solution: Install X11 libraries
sudo apt-get install -y libxtst6 libxrender1 libxi6
```

#### RISC-V Toolchain Issues
```bash
# Issue: GCC not found after installation
# Solution: Verify PATH and re-source environment
echo $PATH | grep riscv
source ~/riscv_setup.sh
which riscv32-unknown-elf-gcc

# Issue: Permission denied errors
# Solution: Fix ownership of tools directory
sudo chown -R $USER:$USER /tools/
```

#### FPGA Board Connection Issues
```bash
# Issue: Board not detected
# Solution: Check USB connection and permissions
lsusb | grep -i digilent
lsusb | grep -i xilinx

# Check and fix USB permissions
sudo usermod -a -G dialout $USER
sudo usermod -a -G plugdev $USER
# Log out and log back in for group changes to take effect

# Issue: Programming fails
# Solution: Check drivers and cable
sudo $XILINX_VIVADO/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers
```

### Build Error Solutions
```bash
# Common Bazel build errors and solutions

# Error: "Cannot find RISC-V toolchain"
# Solution: Verify toolchain installation and PATH
export RISCV_ROOT="/tools/riscv"
export PATH="$RISCV_ROOT/bin:$PATH"

# Error: "Python import errors"
# Solution: Install missing packages
pip3 install --user hjson pyyaml mako

# Error: "Vivado not found"
# Solution: Source Vivado environment
source /tools/Xilinx/Vivado/2023.1/settings64.sh

# Error: "Permission denied" writing to bazel cache
# Solution: Clear and reset Bazel cache
bazel clean --expunge
rm -rf ~/.cache/bazel
```

## Complete Workflow: From Setup to Vulnerability Testing

### Phase 1: Complete Environment Setup (1-2 hours)
```bash
# Step 1: Run auto-installer (30 minutes)
chmod +x ~/install_opentitan_tools.sh
~/install_opentitan_tools.sh

# Step 2: Manual Vivado installation (60 minutes)
# Download from Xilinx website and run GUI installer
~/install_vivado_manual.sh

# Step 3: Verify everything works (5 minutes)
source ~/opentitan_complete_setup.sh
bazel version
vivado -version
riscv32-unknown-elf-gcc --version
openocd --version
```

### Phase 2: OpenTitan FPGA Build (30-60 minutes)
```bash
cd hack@ches_p1_25
source ~/opentitan_complete_setup.sh

# Generate FPGA configuration
./util/topgen.py -t hw/top_earlgrey/data/top_earlgrey.hjson \
                 -o hw/top_earlgrey/ \
                 --rnd_cnst_seed 4881560218204344518

# Build FPGA bitstream (30-60 minutes)
bazel build //hw/bitstream/vivado:fpga_nexys_video

# Build test software
bazel build //sw/device/tests:hello_world_fpga
```

### Phase 3: FPGA Programming and Testing (15 minutes)
```bash
# Connect FPGA board via USB
# Power on board

# Program FPGA with OpenTitan
bazel run //hw/bitstream/vivado:fpga_nexys_video

# Load test software via JTAG
openocd -f board/nexys_video.cfg \
        -c "init; halt; load_image bazel-bin/sw/device/tests/hello_world_fpga.elf; resume; exit"

# Monitor output via UART
screen /dev/ttyUSB1 115200
# Should see: "Hello World from OpenTitan FPGA!"
```

### Phase 4: Dynamic Vulnerability Testing (30 minutes)
```bash
# Build our vulnerability test suite
bazel build //tests/dynamic_analysis:vulnerability_test_framework

# Deploy to FPGA
openocd -f board/nexys_video.cfg \
        -c "init; halt; load_image bazel-bin/tests/dynamic_analysis/vulnerability_test_framework.elf; resume; exit"

# Monitor test results
screen /dev/ttyUSB1 115200
# Watch for vulnerability confirmation messages

# Run timing analysis
python3 tests/dynamic_analysis/timing_analysis.py

# Run power analysis (if equipment available)
python3 tests/dynamic_analysis/power_analysis.py
```

## Summary: Static vs Dynamic Analysis Comparison

### What We Learned

**Static Analysis Results** (what we did first):
- ✅ Found 48 vulnerabilities by reading code
- ✅ Fast and comprehensive coverage  
- ✅ No hardware required
- ❌ Can't verify if vulnerabilities actually work
- ❌ May miss runtime-only issues

**Dynamic Analysis Results** (what we just set up):
- ✅ Proves vulnerabilities actually work on real hardware
- ✅ Finds runtime-only vulnerabilities (timing, power, faults)
- ✅ Tests real-world attack scenarios  
- ❌ Requires expensive FPGA hardware (~$500-800)
- ❌ Takes much longer to set up and run (2-3 hours setup)
- ❌ Limited by FPGA board capabilities

### Combined Approach Benefits

Using both static and dynamic analysis gives us:
1. **Comprehensive Coverage**: Static finds design flaws, dynamic finds implementation issues
2. **Proof of Concept**: Static identifies, dynamic proves exploitability
3. **Competition Advantage**: Shows thorough methodology and real-world validation  
4. **Academic Value**: Demonstrates complete security research process

### Real-World Impact

The FPGA-based dynamic analysis allows us to:
- **Verify our 4 main bug submissions** actually work on real hardware
- **Discover additional runtime vulnerabilities** not visible in static analysis
- **Provide video proof** of exploits for competition judges
- **Develop sophisticated attack techniques** using timing and power analysis
- **Measure actual security impact** in realistic conditions

### Tool Investment Summary

**Required Investment for Dynamic Analysis**:
```
Hardware Costs:
├── FPGA Board (Nexys Video): $500-800
├── JTAG Debugger: $60
├── Cables and accessories: $50
└── Total Hardware: ~$650

Software (All Free):
├── Vivado WebPACK: Free
├── OpenTitan toolchain: Free
├── Development tools: Free
└── Total Software: $0

Time Investment:
├── Setup and installation: 2-3 hours
├── Learning curve: 5-10 hours  
├── Testing and analysis: 2-4 hours per vulnerability
└── Total Time: 15-25 hours
```

### Competition Strategy

For **Hack@CHES'25**, this dynamic analysis approach provides:
- **Differentiation**: Most teams only do static analysis
- **Higher scores**: Proven exploits score more points than theoretical findings
- **Credibility**: Judges value real hardware validation
- **Completeness**: Demonstrates professional security research methodology

This comprehensive approach combining both static and dynamic analysis represents the **gold standard for hardware security research** and significantly strengthens our competition submission.

## Beginner-Friendly Summary

**What we accomplished**:
1. **Static Analysis**: Found security flaws by reading code (like reviewing blueprints)
2. **Dynamic Setup**: Prepared to test flaws on real hardware (like crash-testing the actual car)
3. **Tool Installation**: Set up complete development environment for hardware security testing
4. **Methodology**: Created systematic approach for comprehensive security analysis

**Why this matters**:
- Proves our findings work in the real world
- Discovers vulnerabilities that only appear when hardware actually runs
- Provides complete proof-of-concept exploits for competition
- Demonstrates professional-grade security research capabilities

Even for beginners, this guide provides everything needed to conduct advanced hardware security research using industry-standard tools and methodologies.