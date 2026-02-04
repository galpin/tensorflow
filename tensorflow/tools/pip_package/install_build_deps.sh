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
# Install system build dependencies for building TensorFlow Python wheels on Ubuntu.
#
# This script installs:
#   - Clang compiler (version 14 or later)
#   - Bazelisk (Bazel version manager)
#   - System libraries required for TensorFlow compilation
#
# NOTE: uv and Python must be installed separately as your regular user:
#   curl -LsSf https://astral.sh/uv/install.sh | sh
#   source ~/.cargo/env
#   uv python install 3.11
#
# USAGE:
#   sudo ./install_build_deps.sh [options]
#
# OPTIONS:
#   --clang-version <ver>   Clang version to install (default: 14)
#   --skip-clang            Skip Clang installation
#   --skip-bazel            Skip Bazelisk installation
#   --user <username>       User to create (for Docker builds)
#   --create-user           Create the user if it doesn't exist (for Docker builds)
#   --help                  Show this help message
#
# EXAMPLES:
#   # Install all dependencies with defaults
#   sudo ./install_build_deps.sh
#
#   # Install with Clang 16
#   sudo ./install_build_deps.sh --clang-version 16
#
#   # Docker build: create user and install for them
#   ./install_build_deps.sh --user tensorflow --create-user
#
# NOTES:
#   - This script requires root privileges (sudo) or run as root
#   - Tested on Ubuntu 18.04, 20.04, and 22.04
#
# ==============================================================================

set -e

# Default values
# Note: Clang version will be auto-detected based on Ubuntu version if not specified
CLANG_VERSION=""
SKIP_CLANG=0
SKIP_BAZEL=0
CREATE_USER=0
TARGET_USER="${SUDO_USER:-root}"

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
    head -n 55 "$0" | tail -n +17 | sed 's/^# \?//'
    exit "${1:-0}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clang-version)
            CLANG_VERSION="$2"
            shift 2
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
        --create-user)
            CREATE_USER=1
            shift
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

# Set default Clang version based on Ubuntu version if not specified
if [[ -z "$CLANG_VERSION" ]]; then
    case "$UBUNTU_CODENAME" in
        noble)
            # Ubuntu 24.04: LLVM 14 not available, use Clang 18
            CLANG_VERSION="18"
            ;;
        *)
            # Older Ubuntu versions: use Clang 14
            CLANG_VERSION="14"
            ;;
    esac
    log_info "Auto-selected Clang version: $CLANG_VERSION"
fi

# Create user if requested (for Docker builds)
if [[ $CREATE_USER -eq 1 ]]; then
    if ! id "$TARGET_USER" &>/dev/null; then
        log_info "Creating user: $TARGET_USER"
        # Install sudo first if not present (needed for sudoers.d)
        if ! command -v sudo &>/dev/null; then
            apt-get update && apt-get install -y --no-install-recommends sudo
        fi
        useradd -m -s /bin/bash "$TARGET_USER"
        mkdir -p /etc/sudoers.d
        echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$TARGET_USER
        chmod 0440 /etc/sudoers.d/$TARGET_USER
    fi
fi

log_info "Target user: $TARGET_USER"

# ==============================================================================
# Install system dependencies
# ==============================================================================
log_info "Installing system dependencies..."

apt-get update

apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
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
    sudo \
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
            apt-get install -y --no-install-recommends \
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
# Install Python 3.11 (system-wide via deadsnakes PPA)
# ==============================================================================
log_info "Installing Python 3.11..."

if command -v python3.11 &> /dev/null; then
    log_info "Python 3.11 is already installed"
else
    # Add deadsnakes PPA for Python 3.11
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3.11-dev \
        python3.11-distutils
fi

# Install pip for Python 3.11
if ! python3.11 -m pip --version &> /dev/null; then
    log_info "Installing pip for Python 3.11..."
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11
fi

log_success "Python 3.11 installed"
python3.11 --version

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
# Cleanup (for Docker builds)
# ==============================================================================
if [[ -n "$DOCKER_BUILD" ]] || [[ -f /.dockerenv ]]; then
    log_info "Cleaning up apt cache for smaller image..."
    apt-get clean
    rm -rf /var/lib/apt/lists/*
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

if [[ $SKIP_BAZEL -eq 0 ]]; then
    echo "Bazel:      $(/usr/local/bin/bazel version 2>/dev/null | head -n1 || echo 'Not found')"
fi

echo "=============================================="
echo ""
echo "Next steps (run as your regular user, not root):"
echo ""
echo "  1. Install uv and Python:"
echo "     curl -LsSf https://astral.sh/uv/install.sh | sh"
echo "     source ~/.cargo/env"
echo "     uv python install 3.11"
echo ""
echo "  2. Run the build script:"
echo "     ./tensorflow/tools/pip_package/build_wheel_clang.sh"
echo ""
