#!/usr/bin/env bash
# Copyright 2015 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
#
# Install build dependencies for building TensorFlow Python wheels on Ubuntu.
#
# This script installs:
#   - Clang compiler (version 14 or later)
#   - Python 3.11 via uv (fast Python package manager)
#   - Bazelisk (Bazel version manager)
#   - System libraries required for TensorFlow compilation
#
# USAGE:
#   sudo ./install_build_deps.sh [options]
#
# OPTIONS:
#   --clang-version <ver>   Clang version to install (default: 14)
#   --skip-python           Skip Python 3.11 installation
#   --skip-clang            Skip Clang installation
#   --skip-bazel            Skip Bazelisk installation
#   --user <username>       Install user tools for this user (default: $SUDO_USER)
#   --help                  Show this help message
#
# EXAMPLES:
#   # Install all dependencies with defaults
#   sudo ./install_build_deps.sh
#
#   # Install with Clang 16
#   sudo ./install_build_deps.sh --clang-version 16
#
#   # Skip Python (if already installed)
#   sudo ./install_build_deps.sh --skip-python
#
# NOTES:
#   - This script requires root privileges (sudo)
#   - Tested on Ubuntu 18.04, 20.04, and 22.04
#   - After installation, Python 3.11 will be available as 'python3.11'
#   - uv is installed to ~/.cargo/bin (added to PATH)
#
# ==============================================================================

set -e

# Default values
CLANG_VERSION="14"
SKIP_PYTHON=0
SKIP_CLANG=0
SKIP_BAZEL=0
TARGET_USER="${SUDO_USER:-$USER}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    head -n 50 "$0" | tail -n +17 | sed 's/^# \?//'
    exit "${1:-0}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clang-version)
            CLANG_VERSION="$2"
            shift 2
            ;;
        --skip-python)
            SKIP_PYTHON=1
            shift
            ;;
        --skip-clang)
            SKIP_CLANG=1
            shift
            ;;
        --skip-bazel)
            SKIP_BAZEL=1
            shift
            ;;
        --user)
            TARGET_USER="$2"
            shift 2
            ;;
        --help|-h)
            usage 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Get Ubuntu version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    UBUNTU_VERSION="$VERSION_ID"
    UBUNTU_CODENAME="$VERSION_CODENAME"
else
    log_error "Cannot detect OS version. This script is designed for Ubuntu."
    exit 1
fi

log_info "Detected Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
log_info "Target user: $TARGET_USER"

# Get user's home directory
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z "$TARGET_HOME" ]]; then
    log_error "Cannot determine home directory for user: $TARGET_USER"
    exit 1
fi

# ==============================================================================
# Install system dependencies
# ==============================================================================
log_info "Installing system dependencies..."

apt-get update

apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    pkg-config \
    zip \
    unzip \
    zlib1g-dev \
    libhdf5-dev \
    libssl-dev \
    libffi-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    liblzma-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libgdbm-dev \
    libnss3-dev \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    patchelf \
    swig \
    openjdk-11-jdk

log_success "System dependencies installed"

# ==============================================================================
# Install Clang
# ==============================================================================
if [[ $SKIP_CLANG -eq 0 ]]; then
    log_info "Installing Clang ${CLANG_VERSION}..."

    # Check if clang is already installed with the right version
    if command -v clang-${CLANG_VERSION} &> /dev/null; then
        log_info "Clang ${CLANG_VERSION} is already installed"
    else
        # Add LLVM repository
        wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -

        # Add repository based on Ubuntu version
        case "$UBUNTU_CODENAME" in
            bionic)
                LLVM_REPO="deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic-${CLANG_VERSION} main"
                ;;
            focal)
                LLVM_REPO="deb http://apt.llvm.org/focal/ llvm-toolchain-focal-${CLANG_VERSION} main"
                ;;
            jammy)
                LLVM_REPO="deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-${CLANG_VERSION} main"
                ;;
            noble)
                LLVM_REPO="deb http://apt.llvm.org/noble/ llvm-toolchain-noble-${CLANG_VERSION} main"
                ;;
            *)
                log_warning "Unknown Ubuntu version, attempting default Clang install"
                apt-get install -y clang lld
                CLANG_VERSION=""
                ;;
        esac

        if [[ -n "$CLANG_VERSION" ]]; then
            echo "$LLVM_REPO" > /etc/apt/sources.list.d/llvm.list
            apt-get update
            apt-get install -y \
                clang-${CLANG_VERSION} \
                clang++-${CLANG_VERSION} \
                lld-${CLANG_VERSION} \
                llvm-${CLANG_VERSION} \
                llvm-${CLANG_VERSION}-dev \
                libc++-${CLANG_VERSION}-dev \
                libc++abi-${CLANG_VERSION}-dev
        fi
    fi

    # Set up alternatives for clang/clang++
    if [[ -n "$CLANG_VERSION" ]]; then
        update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100
        update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 100
        update-alternatives --install /usr/bin/lld lld /usr/bin/lld-${CLANG_VERSION} 100

        log_success "Clang ${CLANG_VERSION} installed and configured"
        clang --version
    fi
else
    log_info "Skipping Clang installation"
fi

# ==============================================================================
# Install uv and Python 3.11
# ==============================================================================
if [[ $SKIP_PYTHON -eq 0 ]]; then
    log_info "Installing uv (Python package manager)..."

    # Install uv for the target user
    sudo -u "$TARGET_USER" bash << 'UVINSTALL'
        set -e

        # Install uv if not present
        if ! command -v uv &> /dev/null; then
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi

        # Source cargo env to get uv in path
        if [[ -f "$HOME/.cargo/env" ]]; then
            source "$HOME/.cargo/env"
        fi
UVINSTALL

    log_success "uv installed"

    log_info "Installing Python 3.11 via uv..."

    # Install Python 3.11
    sudo -u "$TARGET_USER" bash << 'PYINSTALL'
        set -e

        # Source cargo env to get uv in path
        if [[ -f "$HOME/.cargo/env" ]]; then
            source "$HOME/.cargo/env"
        fi

        # Install Python 3.11
        uv python install 3.11

        # Show installed Python
        uv python list | grep 3.11 || true
PYINSTALL

    log_success "Python 3.11 installed via uv"

    # Create symlink for python3.11 if it doesn't exist
    PYTHON_UV_PATH=$(sudo -u "$TARGET_USER" bash -c '
        source "$HOME/.cargo/env" 2>/dev/null || true
        uv python find 3.11 2>/dev/null || true
    ')

    if [[ -n "$PYTHON_UV_PATH" && -x "$PYTHON_UV_PATH" ]]; then
        log_info "Python 3.11 location: $PYTHON_UV_PATH"

        # Create a wrapper script for python3.11
        cat > /usr/local/bin/python3.11 << EOF
#!/bin/bash
exec "$PYTHON_UV_PATH" "\$@"
EOF
        chmod +x /usr/local/bin/python3.11
        log_success "Created /usr/local/bin/python3.11 symlink"
    else
        log_warning "Could not create python3.11 symlink. You may need to specify the full path."
        log_info "Use: uv python find 3.11 to locate Python 3.11"
    fi

    # Install required Python packages
    log_info "Installing required Python packages..."
    sudo -u "$TARGET_USER" bash << 'PIPINSTALL'
        set -e
        source "$HOME/.cargo/env" 2>/dev/null || true

        PYTHON_PATH=$(uv python find 3.11)
        if [[ -n "$PYTHON_PATH" ]]; then
            uv pip install --python "$PYTHON_PATH" \
                numpy \
                wheel \
                setuptools \
                packaging \
                requests
        fi
PIPINSTALL

    log_success "Python packages installed"
else
    log_info "Skipping Python installation"
fi

# ==============================================================================
# Install Bazelisk
# ==============================================================================
if [[ $SKIP_BAZEL -eq 0 ]]; then
    log_info "Installing Bazelisk..."

    # Determine architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            BAZEL_ARCH="amd64"
            ;;
        aarch64)
            BAZEL_ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Download and install Bazelisk
    BAZELISK_VERSION="v1.19.0"
    BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-${BAZEL_ARCH}"

    wget -q "$BAZELISK_URL" -O /usr/local/bin/bazel
    chmod +x /usr/local/bin/bazel

    # Verify installation
    if /usr/local/bin/bazel version 2>/dev/null | head -n1; then
        log_success "Bazelisk installed at /usr/local/bin/bazel"
    else
        log_warning "Bazelisk installed but version check failed"
    fi
else
    log_info "Skipping Bazel installation"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "=============================================="
echo "Installation Summary"
echo "=============================================="

if [[ $SKIP_CLANG -eq 0 ]]; then
    echo "Clang:      $(clang --version 2>/dev/null | head -n1 || echo 'Not found')"
fi

if [[ $SKIP_PYTHON -eq 0 ]]; then
    echo "Python:     $(python3.11 --version 2>/dev/null || echo 'Use: uv python find 3.11')"
    echo "uv:         Installed for user $TARGET_USER"
fi

if [[ $SKIP_BAZEL -eq 0 ]]; then
    echo "Bazel:      $(/usr/local/bin/bazel version 2>/dev/null | head -n1 || echo 'Not found')"
fi

echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Log out and log back in (or run: source ~/.cargo/env)"
echo "  2. Run the build script:"
echo "     ./tensorflow/tools/pip_package/build_wheel_clang.sh"
echo ""

# Add cargo to PATH hint
if [[ $SKIP_PYTHON -eq 0 ]]; then
    log_info "To use uv immediately, run:"
    echo "  source ~/.cargo/env"
fi
