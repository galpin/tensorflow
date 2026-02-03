# TensorFlow Dev Container

Build TensorFlow Python wheels in a Linux environment from macOS or Windows.

## Quick Start

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) and [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

2. Open this repository in VS Code

3. Click **"Reopen in Container"** when prompted

4. Build a wheel:
   ```bash
   ./tensorflow/tools/pip_package/build_wheel_clang.sh
   ```

## What's Installed

The container uses `install_build_deps.sh` to install:

- **Ubuntu 22.04** base
- **Clang 14** (configurable)
- **Python 3.11** via uv
- **Bazelisk** (auto Bazel versioning)
- All TensorFlow build dependencies

## Resource Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| Memory | 8 GB | 16+ GB |
| CPU | 4 cores | 8+ cores |
| Disk | 20 GB | 50+ GB |

Adjust in `devcontainer.json`:
```json
"runArgs": ["--memory=16g", "--cpus=8"]
```

## Command Line Usage

```bash
# Build container
docker build -t tf-builder -f .devcontainer/Dockerfile .

# Run
docker run -it --rm -v $(pwd):/workspace tf-builder

# Build wheel inside container
./tensorflow/tools/pip_package/build_wheel_clang.sh
```

## Customization

### Clang Version

Edit `devcontainer.json`:
```json
"build": { "args": { "CLANG_VERSION": "16" } }
```

### Target CPU

```bash
./tensorflow/tools/pip_package/build_wheel_clang.sh --cpu skylake
```

## Apple Silicon

Docker uses Rosetta 2 emulation on M1/M2/M3 Macs. Builds are slower but produce valid Linux x86_64 wheels.
