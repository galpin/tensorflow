# TensorFlow Development Container
# Minimal base image - run install_build_deps.sh manually after container starts

FROM ubuntu:24.04

ARG USERNAME=tensorflow
ARG USER_UID=10042
ARG USER_GID=$USER_UID

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Fix apt pipelining issues with ARM64 mirrors
RUN echo 'Acquire::http::Pipeline-Depth "0";' > /etc/apt/apt.conf.d/99fixbadproxy \
    && echo 'Acquire::http::No-Cache "true";' >> /etc/apt/apt.conf.d/99fixbadproxy \
    && echo 'Acquire::BrokenProxy "true";' >> /etc/apt/apt.conf.d/99fixbadproxy

# Create non-root user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && apt-get update \
    && apt-get install -y --no-install-recommends sudo \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER $USERNAME
WORKDIR /workspace/tensorflow/tools/pip_package

CMD ["/bin/bash"]
