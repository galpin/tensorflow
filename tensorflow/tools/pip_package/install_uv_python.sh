#!/usr/bin/env bash
# Install uv and Python for TensorFlow wheel builds
#
# Run this as your regular user (NOT root/sudo):
#   ./install_uv_python.sh
#
# This installs:
#   - uv (fast Python package manager)
#   - Python 3.11 (or specify version with --python)
#
# ==============================================================================

set -e

PYTHON_VERSION="${1:-3.11}"

echo "[INFO] Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | sh

echo "[INFO] Sourcing uv..."
source "$HOME/.cargo/env"

echo "[INFO] Installing Python ${PYTHON_VERSION}..."
uv python install "$PYTHON_VERSION"

echo ""
echo "=============================================="
echo "Installation complete!"
echo "=============================================="
echo "uv:     $(uv --version)"
echo "Python: $(uv python find $PYTHON_VERSION)"
echo "=============================================="
echo ""
echo "To use uv in new shells, add to your ~/.bashrc:"
echo "  source ~/.cargo/env"
echo ""
echo "You can now run the build script:"
echo "  ./tensorflow/tools/pip_package/build_wheel_clang.sh"
echo ""
