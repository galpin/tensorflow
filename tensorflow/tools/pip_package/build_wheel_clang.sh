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
# Build a TensorFlow wheel using Clang compiler with custom CPU optimization.
#
# This script builds TensorFlow optimized for a specific CPU architecture that
# may differ from the build machine. It automatically creates a virtual
# environment using the system Python.
#
# PREREQUISITES:
#   Run install_build_deps.sh first to install required dependencies:
#     sudo ./tensorflow/tools/pip_package/install_build_deps.sh
#
# USAGE:
#   ./build_wheel_clang.sh [options]
#
# OPTIONS:
#   --cpu <arch>        Target CPU architecture (default: znver2)
#   --python <version>  Python version to use (default: 3.11)
#   --venv <dir>        Virtual environment directory (default: .venv)
#   --clang <path>      Path to clang compiler (default: clang)
#   --output <dir>      Output directory for wheel (default: /tmp/tensorflow_wheel)
#   --jobs <n>          Number of parallel build jobs (default: auto)
#   --config <config>   Additional Bazel config (can be repeated)
#   --opt-level <level> Optimization level: O1, O2, O3, Ofast (default: O3)
#   --lto               Enable Link Time Optimization
#   --project-name <n>  Custom project name for the wheel
#   --help              Show this help message
#
# EXAMPLES:
#   # Build with defaults (Python 3.11, znver2)
#   ./build_wheel_clang.sh
#
#   # Build with Python 3.12
#   ./build_wheel_clang.sh --python 3.12
#
#   # Build with custom venv location
#   ./build_wheel_clang.sh --venv /tmp/tf-venv
#
#   # Build with LTO for maximum performance
#   ./build_wheel_clang.sh --lto
#
# SUPPORTED CPU ARCHITECTURES:
#
#   AMD (Zen Family):
#     znver1          Zen 1 (EPYC 7001, Ryzen 1000/2000)
#     znver2          Zen 2 (EPYC 7002 "Rome", Ryzen 3000) <- AMD EPYC 7702
#     znver3          Zen 3 (EPYC 7003 "Milan", Ryzen 5000)
#     znver4          Zen 4 (EPYC 9004 "Genoa", Ryzen 7000)
#
#   Intel:
#     haswell         4th Gen Core, Xeon E5 v3
#     broadwell       5th Gen Core, Xeon E5 v4
#     skylake         6th Gen Core
#     skylake-avx512  Xeon Scalable 1st Gen
#     cascadelake     Xeon Scalable 2nd Gen
#     icelake-server  Xeon Scalable 3rd Gen
#     sapphirerapids  Xeon Scalable 4th Gen
#
#   Generic:
#     x86-64          Baseline x86_64 (maximum compatibility)
#     x86-64-v2       + SSE4.2, SSSE3, POPCNT
#     x86-64-v3       + AVX2, BMI1/2, FMA
#     x86-64-v4       + AVX-512
#     native          Auto-detect build machine's CPU
#
# ==============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
TARGET_CPU="znver2"
PYTHON_VERSION="3.11"
VENV_DIR="${TF_ROOT}/.venv"
CLANG_PATH="clang"
OUTPUT_DIR="/tmp/tensorflow_wheel"
BUILD_JOBS=""
EXTRA_CONFIGS=()
OPT_LEVEL="O3"
ENABLE_LTO=0
PROJECT_NAME=""

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
    head -n 80 "$0" | tail -n +17 | sed 's/^# \?//'
    exit "${1:-0}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            TARGET_CPU="$2"
            shift 2
            ;;
        --python)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        --venv)
            VENV_DIR="$2"
            shift 2
            ;;
        --clang)
            CLANG_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --jobs)
            BUILD_JOBS="$2"
            shift 2
            ;;
        --config)
            EXTRA_CONFIGS+=("$2")
            shift 2
            ;;
        --opt-level)
            OPT_LEVEL="$2"
            shift 2
            ;;
        --lto)
            ENABLE_LTO=1
            shift
            ;;
        --project-name)
            PROJECT_NAME="$2"
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

# Validate optimization level
case "$OPT_LEVEL" in
    O1|O2|O3|Ofast|Os|Oz)
        ;;
    *)
        log_error "Invalid optimization level: $OPT_LEVEL. Must be one of: O1, O2, O3, Ofast, Os, Oz"
        exit 1
        ;;
esac

# Check for required tools
check_tool() {
    local tool="$1"
    local path="$2"
    if ! command -v "$path" &> /dev/null; then
        log_error "$tool not found at: $path"
        log_info "Run install_build_deps.sh to install dependencies"
        exit 1
    fi
}

log_info "Checking required tools..."
check_tool "Clang" "$CLANG_PATH"
check_tool "Bazel" "bazel"
check_tool "Python ${PYTHON_VERSION}" "python${PYTHON_VERSION}"

# Get absolute paths
CLANG_PATH="$(command -v "$CLANG_PATH")"
CLANGXX_PATH="${CLANG_PATH}++"

# Check clang++ exists
if ! command -v "$CLANGXX_PATH" &> /dev/null; then
    CLANG_DIR="$(dirname "$CLANG_PATH")"
    if [[ -x "${CLANG_DIR}/clang++" ]]; then
        CLANGXX_PATH="${CLANG_DIR}/clang++"
    else
        log_error "clang++ not found. Please ensure clang++ is installed."
        exit 1
    fi
fi

# ==============================================================================
# Create virtual environment with system Python
# ==============================================================================
log_info "Setting up Python ${PYTHON_VERSION} virtual environment..."

# Create venv directory path (absolute)
if [[ "${VENV_DIR:0:1}" != "/" ]]; then
    VENV_DIR="${TF_ROOT}/${VENV_DIR}"
fi

# Create or reuse virtual environment
if [[ -d "$VENV_DIR" ]]; then
    log_info "Using existing virtual environment: $VENV_DIR"
else
    log_info "Creating virtual environment with Python ${PYTHON_VERSION}..."
    "python${PYTHON_VERSION}" -m venv "$VENV_DIR"
    log_success "Virtual environment created: $VENV_DIR"
fi

# Activate virtual environment
log_info "Activating virtual environment..."
source "${VENV_DIR}/bin/activate"

# Get Python path from venv
PYTHON_BIN="${VENV_DIR}/bin/python"

# Verify Python version
ACTUAL_PYTHON_VERSION=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if [[ "$ACTUAL_PYTHON_VERSION" != "$PYTHON_VERSION" ]]; then
    log_warning "Python version is $ACTUAL_PYTHON_VERSION, expected $PYTHON_VERSION"
fi

# Install required packages
log_info "Installing required Python packages..."
pip install --upgrade pip
pip install numpy wheel setuptools packaging requests six mock

log_success "Virtual environment ready: Python $ACTUAL_PYTHON_VERSION"

# ==============================================================================
# Validate build configuration
# ==============================================================================
CLANG_VERSION=$("$CLANG_PATH" --version | head -n1)
log_info "Using Clang: $CLANG_VERSION"
log_info "Using Python: $PYTHON_BIN (version $ACTUAL_PYTHON_VERSION)"
log_info "Target CPU architecture: $TARGET_CPU"
log_info "Optimization level: -$OPT_LEVEL"
log_info "Output directory: $OUTPUT_DIR"

# Verify the target CPU is valid
log_info "Validating target CPU architecture..."
if ! "$CLANG_PATH" -march="$TARGET_CPU" -x c -c /dev/null -o /dev/null 2>/dev/null; then
    log_error "Invalid CPU architecture: $TARGET_CPU"
    log_info "Run 'clang --print-supported-cpus' to see supported CPU architectures"
    exit 1
fi
log_success "CPU architecture '$TARGET_CPU' is valid"

# Create output directory
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Change to TensorFlow root
cd "$TF_ROOT"
log_info "Working in TensorFlow root: $TF_ROOT"

# Build compiler flags
CPU_OPT_FLAGS="-march=${TARGET_CPU} -mtune=${TARGET_CPU} -${OPT_LEVEL}"

if [[ $ENABLE_LTO -eq 1 ]]; then
    CPU_OPT_FLAGS="${CPU_OPT_FLAGS} -flto=thin"
    log_info "LTO enabled (thin LTO)"
fi

log_info "CPU optimization flags: $CPU_OPT_FLAGS"

# ==============================================================================
# Create temporary bazelrc
# ==============================================================================
TEMP_BAZELRC="$(mktemp)"
trap "rm -f $TEMP_BAZELRC" EXIT

cat > "$TEMP_BAZELRC" << EOF
# Temporary bazelrc for Clang wheel build
# Target CPU: ${TARGET_CPU}
# Python: ${ACTUAL_PYTHON_VERSION}
# Generated by build_wheel_clang.sh

# Use Clang as the compiler
build:clang_wheel --action_env=CC=${CLANG_PATH}
build:clang_wheel --action_env=CXX=${CLANGXX_PATH}
build:clang_wheel --repo_env=CC=${CLANG_PATH}
build:clang_wheel --repo_env=CXX=${CLANGXX_PATH}

# CPU optimization flags for target architecture
build:clang_wheel --copt=-march=${TARGET_CPU}
build:clang_wheel --copt=-mtune=${TARGET_CPU}
build:clang_wheel --copt=-${OPT_LEVEL}
build:clang_wheel --host_copt=-${OPT_LEVEL}

# Additional Clang-specific optimizations
build:clang_wheel --copt=-fno-omit-frame-pointer
build:clang_wheel --copt=-ffunction-sections
build:clang_wheel --copt=-fdata-sections
build:clang_wheel --linkopt=-Wl,--gc-sections

# Suppress warnings
build:clang_wheel --copt=-Wno-unused-command-line-argument
build:clang_wheel --copt=-Wno-unknown-warning-option

# Python configuration
build:clang_wheel --action_env=PYTHON_BIN_PATH=${PYTHON_BIN}
build:clang_wheel --python_path=${PYTHON_BIN}

EOF

if [[ $ENABLE_LTO -eq 1 ]]; then
    cat >> "$TEMP_BAZELRC" << EOF
# Link Time Optimization
build:clang_wheel --copt=-flto=thin
build:clang_wheel --linkopt=-flto=thin
build:clang_wheel --linkopt=-Wl,--thinlto-cache-dir=/tmp/thinlto-cache
EOF
fi

log_info "Created temporary bazelrc: $TEMP_BAZELRC"

# ==============================================================================
# Build TensorFlow
# ==============================================================================
BAZEL_BUILD_FLAGS=(
    "--config=opt"
    "--config=clang_wheel"
    "--bazelrc=${TEMP_BAZELRC}"
)

for config in "${EXTRA_CONFIGS[@]}"; do
    BAZEL_BUILD_FLAGS+=("--config=${config}")
done

if [[ -n "$BUILD_JOBS" ]]; then
    BAZEL_BUILD_FLAGS+=("--jobs=${BUILD_JOBS}")
fi

log_info "Starting TensorFlow build..."
log_info "Bazel flags: ${BAZEL_BUILD_FLAGS[*]}"

log_info "Cleaning previous build artifacts..."
bazel clean --expunge 2>/dev/null || true

log_info "Building TensorFlow pip package..."
bazel build \
    "${BAZEL_BUILD_FLAGS[@]}" \
    //tensorflow/tools/pip_package:build_pip_package

if [[ $? -ne 0 ]]; then
    log_error "Bazel build failed"
    exit 1
fi

log_success "Bazel build completed successfully"

# ==============================================================================
# Build wheel
# ==============================================================================
WHEEL_TMPDIR="$(mktemp -d)"
trap "rm -rf $WHEEL_TMPDIR $TEMP_BAZELRC" EXIT

log_info "Building Python wheel..."

export PYTHON_BIN_PATH="$PYTHON_BIN"

PKG_NAME_FLAG=""
if [[ -n "$PROJECT_NAME" ]]; then
    PKG_NAME_FLAG="--project_name ${PROJECT_NAME}"
fi

./bazel-bin/tensorflow/tools/pip_package/build_pip_package \
    --src "$WHEEL_TMPDIR" \
    --dst "$OUTPUT_DIR" \
    $PKG_NAME_FLAG

if [[ $? -ne 0 ]]; then
    log_error "Wheel build failed"
    exit 1
fi

WHEEL_FILE=$(ls -t "${OUTPUT_DIR}"/*.whl 2>/dev/null | head -n1)

if [[ -z "$WHEEL_FILE" ]]; then
    log_error "No wheel file found in output directory"
    exit 1
fi

log_success "Wheel built successfully!"
echo ""
echo "=============================================="
echo "Build Summary"
echo "=============================================="
echo "Target CPU:      $TARGET_CPU"
echo "Optimization:    -$OPT_LEVEL"
echo "LTO:             $([ $ENABLE_LTO -eq 1 ] && echo 'Enabled' || echo 'Disabled')"
echo "Python:          $ACTUAL_PYTHON_VERSION"
echo "Virtual env:     $VENV_DIR"
echo "Clang:           $CLANG_VERSION"
echo "Wheel:           $WHEEL_FILE"
echo "=============================================="
echo ""
echo "To install the wheel:"
echo "  pip install $WHEEL_FILE"
echo ""
