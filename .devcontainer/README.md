# TensorFlow Dev Container

This dev container provides a complete Linux build environment for building TensorFlow Python wheels with Clang, optimized for AMD EPYC 7702 (znver2) processors.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (macOS/Windows)
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

Or alternatively:
- [GitHub Codespaces](https://github.com/features/codespaces)

## Quick Start

### VS Code

1. Open this repository in VS Code
2. When prompted, click "Reopen in Container" (or press `F1` → "Dev Containers: Reopen in Container")
3. Wait for the container to build (first time takes a few minutes)
4. Start building!

```bash
# Build a wheel optimized for AMD EPYC 7702 (default)
./tensorflow/tools/pip_package/build_wheel_clang.sh

# Build with LTO for maximum performance
./tensorflow/tools/pip_package/build_wheel_clang.sh --lto
```

### Command Line (without VS Code)

```bash
# Build the container
docker build -t tf-builder .devcontainer/

# Run interactively
docker run -it --rm \
    -v $(pwd):/workspace \
    -v tf-bazel-cache:/tmp/bazel_cache \
    --memory=16g \
    --cpus=8 \
    tf-builder

# Inside the container, build the wheel
./tensorflow/tools/pip_package/build_wheel_clang.sh
```

## What's Included

| Component | Version | Notes |
|-----------|---------|-------|
| Ubuntu | 22.04 | Base image |
| Clang | 14 | C/C++ compiler |
| Python | 3.11 | Via uv package manager |
| Bazelisk | Latest | Automatic Bazel version management |
| uv | Latest | Fast Python package manager |

### Pre-installed Python Packages

- numpy
- wheel
- setuptools
- packaging
- requests
- six
- mock

## Resource Requirements

TensorFlow builds are resource-intensive. Recommended minimums:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Memory | 8 GB | 16+ GB |
| CPU Cores | 4 | 8+ |
| Disk Space | 20 GB | 50+ GB |

Adjust resources in `devcontainer.json`:

```json
"runArgs": [
    "--memory=16g",
    "--cpus=8"
]
```

## Caching

The container uses Docker volumes for caching:

- **tf-bazel-cache**: Bazel build cache (significantly speeds up rebuilds)
- **tf-uv-cache**: Python package cache

To clear caches:

```bash
docker volume rm tf-bazel-cache tf-uv-cache
```

## Customization

### Using a Different Clang Version

Edit `.devcontainer/devcontainer.json`:

```json
"build": {
    "args": {
        "CLANG_VERSION": "16"
    }
}
```

### Building for a Different CPU

The build script defaults to `znver2` (AMD EPYC 7702). To target a different CPU:

```bash
# Intel Skylake
./tensorflow/tools/pip_package/build_wheel_clang.sh --cpu skylake

# AMD Zen 3
./tensorflow/tools/pip_package/build_wheel_clang.sh --cpu znver3

# Generic (portable)
./tensorflow/tools/pip_package/build_wheel_clang.sh --cpu x86-64-v3
```

## Troubleshooting

### Build runs out of memory

Increase Docker memory limit:
1. Docker Desktop → Settings → Resources
2. Increase Memory to 16GB or more
3. Update `--memory` in devcontainer.json

### Slow builds

- Ensure Bazel cache volume is mounted
- Increase CPU allocation
- Consider using `--jobs` flag to limit parallelism if memory-constrained:
  ```bash
  ./tensorflow/tools/pip_package/build_wheel_clang.sh --jobs 4
  ```

### Permission issues

The container runs as the `tensorflow` user (UID 1000). If you have permission issues with mounted files:

```bash
# Fix ownership (inside container)
sudo chown -R tensorflow:tensorflow /workspace
```

## Apple Silicon (M1/M2/M3) Notes

When running on Apple Silicon Macs:

1. Docker Desktop will use Rosetta 2 for x86_64 emulation
2. Builds will be slower than native (expect 2-3x longer)
3. The resulting wheel will be for Linux x86_64, not macOS ARM

For native macOS ARM wheels, build directly on macOS instead of using the dev container.
