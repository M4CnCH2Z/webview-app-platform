# GitHub Actions Runner with Kaniko support
FROM ghcr.io/actions/actions-runner:latest

USER root

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Copy Kaniko executor and all dependencies from official image
COPY --from=gcr.io/kaniko-project/executor:v1.24.0 /kaniko /kaniko
ENV PATH="/kaniko:${PATH}"

# Create symlink for easier access
RUN ln -s /kaniko/executor /usr/local/bin/kaniko

# Verify installations
RUN aws --version && \
    /kaniko/executor version && \
    git --version

USER runner

WORKDIR /home/runner
