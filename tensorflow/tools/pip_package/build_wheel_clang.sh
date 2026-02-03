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
# Build a Python 3.11 TensorFlow wheel using Clang compiler with custom CPU
# optimization flags.
#
# This script builds TensorFlow optimized for a specific CPU architecture that
# may differ from the build machine. This is useful for cross-optimization
# scenarios where you want to build on one machine but deploy on another with
# a different CPU.
#
# PREREQUISITES:
#   Run install_build_deps.sh first to install required dependencies:
#     ./tensorflow/tools/pip_package/install_build_deps.sh
#
# USAGE:
#   ./build_wheel_clang.sh [options]
#
# OPTIONS:
#   --cpu <arch>        Target CPU architecture for optimization
#                       Default: znver2 (AMD EPYC 7702 / Zen 2)
#   --python <path>     Path to Python 3.11 interpreter (default: python3.11)
#   --clang <path>      Path to clang compiler (default: clang)
#   --output <dir>      Output directory for the wheel (default: /tmp/tensorflow_wheel)
#   --jobs <n>          Number of parallel build jobs (default: auto)
#   --config <config>   Additional Bazel config (can be specified multiple times)
#   --opt-level <level> Optimization level: O1, O2, O3, Ofast (default: O3)
#   --lto               Enable Link Time Optimization (slower build, faster runtime)
#   --project-name <n>  Custom project name for the wheel
#   --help              Show this help message
#
# EXAMPLES:
#   # Build with defaults (optimized for AMD EPYC 7702 / znver2)
#   ./build_wheel_clang.sh
#
#   # Build optimized for AMD EPYC 7702 (Zen 2 / Rome) - RECOMMENDED
#   ./build_wheel_clang.sh --cpu znver2
#
#   # Build with LTO for maximum performance (longer build time)
#   ./build_wheel_clang.sh --cpu znver2 --lto
#
#   # Build optimized for Intel Skylake
#   ./build_wheel_clang.sh --cpu skylake
#
#   # Build optimized for the build machine's CPU
#   ./build_wheel_clang.sh --cpu native
#
#   # Build with custom Python path (e.g., using uv-managed Python)
#   ./build_wheel_clang.sh --python ~/.local/share/uv/python/cpython-3.11.*/bin/python3.11
#
# SUPPORTED CPU ARCHITECTURES:
#
#   AMD (Zen Family) - Recommended for EPYC/Ryzen:
#     znver1          Zen 1 (EPYC 7001, Ryzen 1000/2000)
#     znver2          Zen 2 (EPYC 7002 "Rome", Ryzen 3000) <- AMD EPYC 7702
#     znver3          Zen 3 (EPYC 7003 "Milan", Ryzen 5000)
#     znver4          Zen 4 (EPYC 9004 "Genoa", Ryzen 7000)
#
#   Intel (Common Server/Desktop):
#     haswell         4th Gen Core, Xeon E5 v3 (2013)
#     broadwell       5th Gen Core, Xeon E5 v4 (2015)
#     skylake         6th Gen Core (2015)
#     skylake-avx512  Xeon Scalable 1st Gen "Skylake-SP" (2017)
#     cascadelake     Xeon Scalable 2nd Gen (2019)
#     icelake-server  Xeon Scalable 3rd Gen (2021)
#     sapphirerapids  Xeon Scalable 4th Gen (2023)
#
#   Generic (Portable builds):
#     x86-64          Baseline x86_64 (maximum compatibility)
#     x86-64-v2       + SSE4.2, SSSE3, POPCNT (Nehalem+)
#     x86-64-v3       + AVX2, BMI1/2, FMA (Haswell+)
#     x86-64-v4       + AVX-512 (Skylake-X+)
#     native          Auto-detect build machine's CPU
#
# CPU FEATURES ENABLED BY znver2 (AMD EPYC 7702):
#   - AVX2: 256-bit vector operations for matrix math
#   - FMA: Fused multiply-add for neural network layers
#   - SSE4.1/SSE4.2: Streaming SIMD extensions
#   - BMI1/BMI2: Bit manipulation instructions
#   - SHA-NI: Hardware SHA acceleration
#   - ADX: Multi-precision arithmetic
#   - CLFLUSHOPT: Optimized cache line flush
#
# ==============================================================================

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values - optimized for AMD EPYC 7702 (Zen 2)
TARGET_CPU="znver2"
PYTHON_BIN="python3.11"
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
    head -n 95 "$0" | tail -n +17 | sed 's/^# \?//'
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
            PYTHON_BIN="$2"
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
check_tool "Python" "$PYTHON_BIN"
check_tool "Bazel" "bazel"

# Verify Python version is 3.11
PYTHON_VERSION=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
if [[ "$PYTHON_VERSION" != "3.11" ]]; then
    log_warning "Python version is $PYTHON_VERSION, expected 3.11"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get absolute paths
PYTHON_BIN="$(command -v "$PYTHON_BIN")"
CLANG_PATH="$(command -v "$CLANG_PATH")"
CLANGXX_PATH="${CLANG_PATH}++"

# Check clang++ exists
if ! command -v "$CLANGXX_PATH" &> /dev/null; then
    # Try to find clang++ in the same directory
    CLANG_DIR="$(dirname "$CLANG_PATH")"
    if [[ -x "${CLANG_DIR}/clang++" ]]; then
        CLANGXX_PATH="${CLANG_DIR}/clang++"
    else
        log_error "clang++ not found. Please ensure clang++ is installed."
        exit 1
    fi
fi

# Get clang version
CLANG_VERSION=$("$CLANG_PATH" --version | head -n1)
log_info "Using Clang: $CLANG_VERSION"
log_info "Using Python: $PYTHON_BIN (version $PYTHON_VERSION)"
log_info "Target CPU architecture: $TARGET_CPU"
log_info "Optimization level: -$OPT_LEVEL"
log_info "Output directory: $OUTPUT_DIR"

# Verify the target CPU is valid by testing with clang
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

# Add LTO flags if enabled
if [[ $ENABLE_LTO -eq 1 ]]; then
    CPU_OPT_FLAGS="${CPU_OPT_FLAGS} -flto=thin"
    log_info "LTO enabled (thin LTO)"
fi

log_info "CPU optimization flags: $CPU_OPT_FLAGS"

# Create temporary bazelrc for this build
TEMP_BAZELRC="$(mktemp)"
trap "rm -f $TEMP_BAZELRC" EXIT

cat > "$TEMP_BAZELRC" << EOF
# Temporary bazelrc for Clang Python 3.11 wheel build
# Target CPU: ${TARGET_CPU}
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

# Suppress warnings (Clang is more strict)
build:clang_wheel --copt=-Wno-unused-command-line-argument
build:clang_wheel --copt=-Wno-unknown-warning-option

# Python configuration
build:clang_wheel --action_env=PYTHON_BIN_PATH=${PYTHON_BIN}
build:clang_wheel --python_path=${PYTHON_BIN}

EOF

# Add LTO configuration if enabled
if [[ $ENABLE_LTO -eq 1 ]]; then
    cat >> "$TEMP_BAZELRC" << EOF
# Link Time Optimization
build:clang_wheel --copt=-flto=thin
build:clang_wheel --linkopt=-flto=thin
build:clang_wheel --linkopt=-Wl,--thinlto-cache-dir=/tmp/thinlto-cache
EOF
fi

log_info "Created temporary bazelrc: $TEMP_BAZELRC"

# Build Bazel command
BAZEL_BUILD_FLAGS=(
    "--config=opt"
    "--config=clang_wheel"
    "--bazelrc=${TEMP_BAZELRC}"
)

# Add extra configs
for config in "${EXTRA_CONFIGS[@]}"; do
    BAZEL_BUILD_FLAGS+=("--config=${config}")
done

# Add job limit if specified
if [[ -n "$BUILD_JOBS" ]]; then
    BAZEL_BUILD_FLAGS+=("--jobs=${BUILD_JOBS}")
fi

log_info "Starting TensorFlow build..."
log_info "Bazel flags: ${BAZEL_BUILD_FLAGS[*]}"

# Clean any previous build artifacts for a fresh build
log_info "Cleaning previous build artifacts..."
bazel clean --expunge 2>/dev/null || true

# Run the Bazel build
log_info "Building TensorFlow pip package..."
bazel build \
    "${BAZEL_BUILD_FLAGS[@]}" \
    //tensorflow/tools/pip_package:build_pip_package

if [[ $? -ne 0 ]]; then
    log_error "Bazel build failed"
    exit 1
fi

log_success "Bazel build completed successfully"

# Create a temporary directory for wheel building
WHEEL_TMPDIR="$(mktemp -d)"
trap "rm -rf $WHEEL_TMPDIR $TEMP_BAZELRC" EXIT

# Build the wheel
log_info "Building Python wheel..."

# Set PYTHON_BIN_PATH for build_pip_package.sh
export PYTHON_BIN_PATH="$PYTHON_BIN"

# Determine project name flag
PKG_NAME_FLAG=""
if [[ -n "$PROJECT_NAME" ]]; then
    PKG_NAME_FLAG="--project_name ${PROJECT_NAME}"
fi

# Run the pip package builder
./bazel-bin/tensorflow/tools/pip_package/build_pip_package \
    --src "$WHEEL_TMPDIR" \
    --dst "$OUTPUT_DIR" \
    $PKG_NAME_FLAG

if [[ $? -ne 0 ]]; then
    log_error "Wheel build failed"
    exit 1
fi

# Find and display the built wheel
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
echo "Python:          $PYTHON_VERSION"
echo "Clang:           $CLANG_VERSION"
echo "Wheel:           $WHEEL_FILE"
echo "=============================================="
echo ""
echo "To install the wheel:"
echo "  pip install $WHEEL_FILE"
echo ""
