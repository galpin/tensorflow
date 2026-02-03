# TensorFlow Development Container
# Optimized for building Python 3.11 wheels with Clang for AMD EPYC 7702 (znver2)
#
# This container provides a complete build environment for TensorFlow including:
# - Clang 14 compiler
# - Python 3.11 via uv
# - Bazelisk (Bazel version manager)
# - All system dependencies for TensorFlow compilation

FROM ubuntu:22.04

LABEL maintainer="TensorFlow Authors"
LABEL description="TensorFlow wheel build environment with Clang and Python 3.11"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set locale
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Build arguments
ARG CLANG_VERSION=14
ARG USERNAME=tensorflow
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    ca-certificates \
    curl \
    wget \
    git \
    pkg-config \
    zip \
    unzip \
    # Compression libraries
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    # SSL/Crypto
    libssl-dev \
    libffi-dev \
    # Database libraries
    libsqlite3-dev \
    libgdbm-dev \
    libnss3-dev \
    # Terminal/UI libraries
    libreadline-dev \
    libncurses5-dev \
    libncursesw5-dev \
    # Math libraries
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    # HDF5 for TensorFlow
    libhdf5-dev \
    # Build tools
    patchelf \
    swig \
    # Java for Bazel
    openjdk-11-jdk \
    # Additional utilities
    sudo \
    vim \
    less \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Install Clang from LLVM repository
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - \
    && echo "deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-${CLANG_VERSION} main" \
        > /etc/apt/sources.list.d/llvm.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        clang-${CLANG_VERSION} \
        clang++-${CLANG_VERSION} \
        lld-${CLANG_VERSION} \
        llvm-${CLANG_VERSION} \
        llvm-${CLANG_VERSION}-dev \
        libc++-${CLANG_VERSION}-dev \
        libc++abi-${CLANG_VERSION}-dev \
    && rm -rf /var/lib/apt/lists/* \
    # Set up alternatives for clang/clang++
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 100 \
    && update-alternatives --install /usr/bin/lld lld /usr/bin/lld-${CLANG_VERSION} 100

# Install Bazelisk
ARG TARGETARCH
RUN BAZELISK_VERSION="v1.19.0" \
    && case "${TARGETARCH}" in \
        amd64) BAZEL_ARCH="amd64" ;; \
        arm64) BAZEL_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && wget -q "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-${BAZEL_ARCH}" \
        -O /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/bazel

# Create non-root user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Switch to non-root user for remaining setup
USER $USERNAME
WORKDIR /home/$USERNAME

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Add cargo/uv to PATH
ENV PATH="/home/$USERNAME/.cargo/bin:${PATH}"

# Install Python 3.11 via uv
RUN /home/$USERNAME/.cargo/bin/uv python install 3.11

# Install Python packages needed for TensorFlow build
RUN PYTHON_PATH=$(/home/$USERNAME/.cargo/bin/uv python find 3.11) \
    && /home/$USERNAME/.cargo/bin/uv pip install --python "$PYTHON_PATH" \
        numpy \
        wheel \
        setuptools \
        packaging \
        requests \
        six \
        mock

# Create symlink for python3.11
RUN PYTHON_PATH=$(/home/$USERNAME/.cargo/bin/uv python find 3.11) \
    && sudo ln -sf "$PYTHON_PATH" /usr/local/bin/python3.11

# Set working directory to TensorFlow source
WORKDIR /workspace

# Environment variables for TensorFlow build
ENV CC=clang
ENV CXX=clang++
ENV TF_PYTHON_VERSION=3.11
ENV PYTHON_BIN_PATH=/usr/local/bin/python3.11

# Default command
CMD ["/bin/bash"]
