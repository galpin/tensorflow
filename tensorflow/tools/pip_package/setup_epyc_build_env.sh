#!/usr/bin/env bash
# Copyright 2024 The TensorFlow Authors. All Rights Reserved.
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
# Setup script for TensorFlow build environment optimized for AMD EPYC on Ubuntu.
#
# This script installs all prerequisites needed to build TensorFlow wheels
# optimized for AMD EPYC processors:
#   - System build dependencies (via apt)
#   - uv (fast Python package manager)
#   - Python 3.11 (via uv)
#   - Clang 18 (optimal compiler for AMD Zen architectures)
#   - Bazelisk (Bazel version manager)
#   - Python packages required for TensorFlow build
#
# Usage:
#     ./setup_epyc_build_env.sh [OPTIONS]
#
# Options:
#     --python-version VERSION   Python version to install (default: 3.11)
#     --clang-version VERSION    Clang version to install (default: 18)
#     --venv-path PATH           Path for virtual environment (default: ./tf-build-venv)
#     --skip-system-deps         Skip system dependency installation (requires sudo)
#     --skip-clang               Skip Clang installation (use system GCC)
#     --use-gcc                  Use GCC instead of Clang
#     --help                     Show this help message
#
# Examples:
#     # Full setup with defaults
#     sudo ./setup_epyc_build_env.sh
#
#     # Custom Python version
#     sudo ./setup_epyc_build_env.sh --python-version 3.12
#
#     # Skip system deps if already installed
#     ./setup_epyc_build_env.sh --skip-system-deps
#
# After running this script, activate the virtual environment:
#     source ./tf-build-venv/bin/activate
#
# Then build TensorFlow with:
#     python tensorflow/tools/pip_package/build_epyc_wheel.py

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
CLANG_VERSION="${CLANG_VERSION:-18}"
VENV_PATH="${VENV_PATH:-./tf-build-venv}"
SKIP_SYSTEM_DEPS="${SKIP_SYSTEM_DEPS:-false}"
SKIP_CLANG="${SKIP_CLANG:-false}"
USE_GCC="${USE_GCC:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

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
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. This script is designed for Ubuntu."
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warning "This script is designed for Ubuntu, detected: $ID"
        log_warning "Proceeding anyway, but some commands may fail."
    fi

    log_info "Detected: $PRETTY_NAME"
}

check_root_for_system_deps() {
    if [[ "$SKIP_SYSTEM_DEPS" == "false" && $EUID -ne 0 ]]; then
        log_error "System dependency installation requires root privileges."
        log_error "Run with sudo or use --skip-system-deps if dependencies are already installed."
        exit 1
    fi
}

show_help() {
    head -50 "$0" | tail -35
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --python-version)
                PYTHON_VERSION="$2"
                shift 2
                ;;
            --clang-version)
                CLANG_VERSION="$2"
                shift 2
                ;;
            --venv-path)
                VENV_PATH="$2"
                shift 2
                ;;
            --skip-system-deps)
                SKIP_SYSTEM_DEPS="true"
                shift
                ;;
            --skip-clang)
                SKIP_CLANG="true"
                shift
                ;;
            --use-gcc)
                USE_GCC="true"
                SKIP_CLANG="true"
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Installation Functions
# =============================================================================

install_system_dependencies() {
    print_header "Installing System Dependencies"

    if [[ "$SKIP_SYSTEM_DEPS" == "true" ]]; then
        log_info "Skipping system dependencies (--skip-system-deps)"
        return 0
    fi

    log_info "Updating package lists..."
    apt-get update

    log_info "Installing build essentials and dependencies..."
    apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        git \
        libcurl4-openssl-dev \
        libffi-dev \
        libssl-dev \
        libtool \
        openjdk-21-jdk \
        patchelf \
        pkg-config \
        rsync \
        software-properties-common \
        swig \
        unzip \
        wget \
        zip \
        zlib1g-dev

    # Install additional libraries for TensorFlow
    apt-get install -y --no-install-recommends \
        libhdf5-dev \
        libbz2-dev \
        liblzma-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        llvm \
        tk-dev \
        xz-utils

    log_success "System dependencies installed"
}

install_clang() {
    print_header "Installing Clang ${CLANG_VERSION}"

    if [[ "$SKIP_CLANG" == "true" ]]; then
        log_info "Skipping Clang installation"
        return 0
    fi

    if [[ "$SKIP_SYSTEM_DEPS" == "true" ]]; then
        log_warning "Cannot install Clang without system dep installation privileges"
        log_warning "Use system Clang or GCC instead"
        return 0
    fi

    # Check if Clang is already installed with the right version
    if command -v clang-${CLANG_VERSION} &> /dev/null; then
        log_info "Clang ${CLANG_VERSION} already installed"
        return 0
    fi

    log_info "Adding LLVM repository..."

    # Get Ubuntu codename
    source /etc/os-release
    UBUNTU_CODENAME="${UBUNTU_CODENAME:-jammy}"

    # Add LLVM repository
    wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc

    # Add the repository
    add-apt-repository -y "deb http://apt.llvm.org/${UBUNTU_CODENAME}/ llvm-toolchain-${UBUNTU_CODENAME}-${CLANG_VERSION} main"

    apt-get update

    log_info "Installing Clang ${CLANG_VERSION}..."
    apt-get install -y --no-install-recommends \
        clang-${CLANG_VERSION} \
        lld-${CLANG_VERSION} \
        libc++-${CLANG_VERSION}-dev \
        libc++abi-${CLANG_VERSION}-dev \
        libclang-${CLANG_VERSION}-dev \
        lldb-${CLANG_VERSION}

    # Set up alternatives so clang/clang++ point to the installed version
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 100
    update-alternatives --install /usr/bin/lld lld /usr/bin/lld-${CLANG_VERSION} 100

    log_success "Clang ${CLANG_VERSION} installed and configured"
}

install_uv() {
    print_header "Installing uv (Python Package Manager)"

    if command -v uv &> /dev/null; then
        log_info "uv is already installed: $(uv --version)"
        return 0
    fi

    log_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Add uv to PATH for current session
    export PATH="$HOME/.local/bin:$PATH"

    # Also add to PATH for future sessions if not already there
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q 'uv' "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    log_success "uv installed: $(uv --version)"
}

install_python() {
    print_header "Installing Python ${PYTHON_VERSION} via uv"

    # Ensure uv is in PATH
    export PATH="$HOME/.local/bin:$PATH"

    log_info "Installing Python ${PYTHON_VERSION}..."
    uv python install "${PYTHON_VERSION}"

    # Get the installed Python path
    PYTHON_PATH=$(uv python find "${PYTHON_VERSION}")
    log_success "Python installed at: ${PYTHON_PATH}"

    echo "${PYTHON_PATH}"
}

install_bazelisk() {
    print_header "Installing Bazelisk"

    if command -v bazel &> /dev/null; then
        BAZEL_INFO=$(bazel --version 2>&1 || true)
        if [[ "$BAZEL_INFO" == *"Bazelisk"* ]] || [[ "$BAZEL_INFO" == *"bazel"* ]]; then
            log_info "Bazel/Bazelisk already installed: $BAZEL_INFO"
            return 0
        fi
    fi

    log_info "Downloading Bazelisk..."

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            BAZELISK_ARCH="amd64"
            ;;
        aarch64)
            BAZELISK_ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    # Get latest Bazelisk release
    BAZELISK_URL="https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${BAZELISK_ARCH}"

    # Install to /usr/local/bin if we have permissions, otherwise ~/.local/bin
    if [[ -w /usr/local/bin ]]; then
        INSTALL_DIR="/usr/local/bin"
    else
        INSTALL_DIR="$HOME/.local/bin"
        mkdir -p "$INSTALL_DIR"
    fi

    curl -fSsL "$BAZELISK_URL" -o "${INSTALL_DIR}/bazel"
    chmod +x "${INSTALL_DIR}/bazel"

    # Verify installation
    log_success "Bazelisk installed at: ${INSTALL_DIR}/bazel"
    "${INSTALL_DIR}/bazel" --version
}

create_virtual_environment() {
    print_header "Creating Virtual Environment"

    # Ensure uv is in PATH
    export PATH="$HOME/.local/bin:$PATH"

    # Get Python path
    PYTHON_PATH=$(uv python find "${PYTHON_VERSION}")

    log_info "Creating virtual environment at: ${VENV_PATH}"
    uv venv --python "${PYTHON_VERSION}" "${VENV_PATH}"

    log_success "Virtual environment created"
}

install_python_packages() {
    print_header "Installing Python Packages"

    # Ensure uv and venv are in PATH
    export PATH="$HOME/.local/bin:$PATH"

    # Activate virtual environment
    source "${VENV_PATH}/bin/activate"

    log_info "Installing TensorFlow build dependencies..."

    # Core build dependencies
    uv pip install --upgrade pip setuptools wheel

    # NumPy - critical for TensorFlow, use version 1.x for compatibility
    uv pip install "numpy>=1.26.0,<2.0.0"

    # Build tools
    uv pip install \
        auditwheel~=5.3.0 \
        packaging \
        requests

    # TensorFlow build requirements
    uv pip install \
        absl-py \
        astunparse \
        flatbuffers \
        gast \
        google-pasta \
        grpcio \
        h5py \
        keras-preprocessing \
        libclang \
        opt-einsum \
        protobuf \
        six \
        termcolor \
        typing-extensions \
        wrapt

    # Testing and development
    uv pip install \
        portpicker \
        psutil \
        py-cpuinfo \
        pylint \
        pytest

    log_success "Python packages installed"
}

configure_compiler_environment() {
    print_header "Configuring Compiler Environment"

    # Create environment setup script
    ENV_SCRIPT="${VENV_PATH}/bin/activate_tf_build"

    cat > "${ENV_SCRIPT}" << 'ENVSCRIPT'
#!/usr/bin/env bash
# TensorFlow Build Environment Activation Script
# Source this file to set up the build environment

# Activate virtual environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/activate"

ENVSCRIPT

    if [[ "$USE_GCC" == "true" ]]; then
        cat >> "${ENV_SCRIPT}" << 'GCCENV'
# Using GCC compiler
export CC=gcc
export CXX=g++
echo "Using GCC compiler: $(gcc --version | head -1)"
GCCENV
    else
        cat >> "${ENV_SCRIPT}" << CLANGENV
# Using Clang compiler (optimized for AMD Zen)
export CC=clang-${CLANG_VERSION}
export CXX=clang++-${CLANG_VERSION}

# Clang-specific optimizations for AMD EPYC
export CFLAGS="-march=znver2 -mtune=znver2 -O3"
export CXXFLAGS="-march=znver2 -mtune=znver2 -O3"

# Use LLD linker for faster linking
export LDFLAGS="-fuse-ld=lld-${CLANG_VERSION}"

echo "Using Clang compiler: \$(clang-${CLANG_VERSION} --version | head -1)"
CLANGENV
    fi

    cat >> "${ENV_SCRIPT}" << 'COMMONENV'

# TensorFlow build configuration
export TF_NEED_CUDA=0
export TF_NEED_ROCM=0
export TF_ENABLE_XLA=1
export TF_DOWNLOAD_CLANG=0
export TF_SET_ANDROID_WORKSPACE=0
export TF_NEED_MPI=0

# OneDNN optimization
export TF_ENABLE_ONEDNN_OPTS=1

# Python configuration
export PYTHON_BIN_PATH="$(which python)"
export PYTHON_LIB_PATH="$(python -c 'import site; print(site.getsitepackages()[0])')"

echo ""
echo "TensorFlow build environment activated!"
echo "Python: ${PYTHON_BIN_PATH}"
echo ""
echo "To build an AMD EPYC optimized wheel, run:"
echo "  python tensorflow/tools/pip_package/build_epyc_wheel.py"
echo ""
COMMONENV

    chmod +x "${ENV_SCRIPT}"

    log_success "Environment script created at: ${ENV_SCRIPT}"
}

print_summary() {
    print_header "Setup Complete!"

    echo ""
    echo "Environment Summary:"
    echo "-------------------"
    echo "  Python Version:    ${PYTHON_VERSION}"
    if [[ "$USE_GCC" == "true" ]]; then
        echo "  Compiler:          GCC"
    else
        echo "  Compiler:          Clang ${CLANG_VERSION}"
    fi
    echo "  Virtual Env:       ${VENV_PATH}"
    echo ""
    echo "Next Steps:"
    echo "-----------"
    echo "  1. Activate the build environment:"
    echo "     source ${VENV_PATH}/bin/activate_tf_build"
    echo ""
    echo "  2. Navigate to TensorFlow source directory"
    echo ""
    echo "  3. Build the optimized wheel:"
    echo "     python tensorflow/tools/pip_package/build_epyc_wheel.py"
    echo ""
    echo "  Or build with custom options:"
    echo "     python tensorflow/tools/pip_package/build_epyc_wheel.py --jobs=64 -v"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    print_header "TensorFlow AMD EPYC Build Environment Setup"
    echo "Python Version: ${PYTHON_VERSION}"
    echo "Clang Version:  ${CLANG_VERSION}"
    echo "Venv Path:      ${VENV_PATH}"

    check_ubuntu
    check_root_for_system_deps

    install_system_dependencies
    install_clang
    install_uv
    install_python
    install_bazelisk
    create_virtual_environment
    install_python_packages
    configure_compiler_environment

    print_summary
}

main "$@"
