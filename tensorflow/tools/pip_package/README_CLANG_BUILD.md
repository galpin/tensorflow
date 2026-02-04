# Building TensorFlow Wheels with Clang

Build TensorFlow Python wheels optimized for specific CPU architectures using Clang.

## Quick Start

```bash
# 1. Install system dependencies (as root)
sudo ./tensorflow/tools/pip_package/install_build_deps.sh

# 2. Install uv and Python (as your regular user)
./tensorflow/tools/pip_package/install_uv_python.sh

# 3. Build the wheel
./tensorflow/tools/pip_package/build_wheel_clang.sh
```

## Detailed Steps

### Step 1: Install System Dependencies

Run as root to install Clang, Bazel, and required libraries:

```bash
sudo ./tensorflow/tools/pip_package/install_build_deps.sh
```

Options:
```bash
# Use a specific Clang version
sudo ./tensorflow/tools/pip_package/install_build_deps.sh --clang-version 16

# Skip Clang (if already installed)
sudo ./tensorflow/tools/pip_package/install_build_deps.sh --skip-clang

# Skip Bazel (if already installed)
sudo ./tensorflow/tools/pip_package/install_build_deps.sh --skip-bazel
```

### Step 2: Install uv and Python

Run as your regular user (not root):

```bash
./tensorflow/tools/pip_package/install_uv_python.sh
```

Or manually:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.cargo/env
uv python install 3.11
```

For a different Python version:
```bash
./tensorflow/tools/pip_package/install_uv_python.sh 3.12
```

### Step 3: Build the Wheel

```bash
./tensorflow/tools/pip_package/build_wheel_clang.sh
```

The script will:
- Create a virtual environment using uv
- Install required Python packages
- Build TensorFlow with Clang
- Output the wheel to `/tmp/tensorflow_wheel/`

## Build Options

```bash
# Target CPU architecture (default: znver2 for AMD EPYC 7702)
./build_wheel_clang.sh --cpu skylake

# Python version (default: 3.11)
./build_wheel_clang.sh --python 3.12

# Custom virtualenv location (default: .venv)
./build_wheel_clang.sh --venv /tmp/tf-build-venv

# Output directory (default: /tmp/tensorflow_wheel)
./build_wheel_clang.sh --output ./wheels

# Optimization level (default: O3)
./build_wheel_clang.sh --opt-level Ofast

# Enable Link Time Optimization (slower build, faster runtime)
./build_wheel_clang.sh --lto

# Limit parallel jobs
./build_wheel_clang.sh --jobs 8

# Combine options
./build_wheel_clang.sh --cpu znver2 --python 3.11 --lto --jobs 16
```

## Supported CPU Architectures

### AMD (Zen Family)
| Architecture | CPUs |
|--------------|------|
| `znver1` | EPYC 7001, Ryzen 1000/2000 |
| `znver2` | EPYC 7002 "Rome", Ryzen 3000 (default) |
| `znver3` | EPYC 7003 "Milan", Ryzen 5000 |
| `znver4` | EPYC 9004 "Genoa", Ryzen 7000 |

### Intel
| Architecture | CPUs |
|--------------|------|
| `haswell` | 4th Gen Core, Xeon E5 v3 |
| `broadwell` | 5th Gen Core, Xeon E5 v4 |
| `skylake` | 6th Gen Core |
| `skylake-avx512` | Xeon Scalable 1st Gen |
| `cascadelake` | Xeon Scalable 2nd Gen |
| `icelake-server` | Xeon Scalable 3rd Gen |
| `sapphirerapids` | Xeon Scalable 4th Gen |

### Generic (Portable)
| Architecture | Features |
|--------------|----------|
| `x86-64` | Baseline (maximum compatibility) |
| `x86-64-v2` | + SSE4.2, SSSE3, POPCNT |
| `x86-64-v3` | + AVX2, BMI1/2, FMA |
| `x86-64-v4` | + AVX-512 |
| `native` | Auto-detect build machine |

## Dev Container (macOS/Windows)

Build in a Linux container from macOS or Windows:

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and [VS Code](https://code.visualstudio.com/)
2. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Open this repo in VS Code
4. Click "Reopen in Container"
5. Run in the container terminal:

```bash
# Install system deps
sudo ./tensorflow/tools/pip_package/install_build_deps.sh

# Install uv/Python
./tensorflow/tools/pip_package/install_uv_python.sh

# Build
./tensorflow/tools/pip_package/build_wheel_clang.sh
```

## Installing the Built Wheel

```bash
pip install /tmp/tensorflow_wheel/tensorflow-*.whl
```

## Troubleshooting

### Build runs out of memory
Limit parallel jobs:
```bash
./build_wheel_clang.sh --jobs 4
```

### Clang not found
Ensure Clang is in PATH or specify the path:
```bash
./build_wheel_clang.sh --clang /usr/bin/clang-14
```

### uv not found
Source the cargo environment:
```bash
source ~/.cargo/env
```

### Wrong Python version in venv
Delete the venv and rebuild:
```bash
rm -rf .venv
./build_wheel_clang.sh --python 3.11
```
