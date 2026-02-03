# TensorFlow Development Container
# Minimal Dockerfile that uses install_build_deps.sh for setup

FROM ubuntu:22.04

ARG USERNAME=tensorflow
ARG USER_UID=1000
ARG USER_GID=$USER_UID
ARG CLANG_VERSION=14

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Copy the install script
COPY tensorflow/tools/pip_package/install_build_deps.sh /tmp/install_build_deps.sh

# Run the install script
RUN chmod +x /tmp/install_build_deps.sh && \
    /tmp/install_build_deps.sh \
        --user ${USERNAME} \
        --create-user \
        --clang-version ${CLANG_VERSION} && \
    rm /tmp/install_build_deps.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER ${USERNAME}
WORKDIR /workspace

# Environment
ENV CC=clang
ENV CXX=clang++
ENV PATH="/home/${USERNAME}/.cargo/bin:${PATH}"

CMD ["/bin/bash"]
