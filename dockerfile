# https://github.com/docker-library/docker/issues/306#issuecomment-815338333

# FROM ubuntu:latest AS base
FROM mcr.microsoft.com/playwright/python:v1.50.0-noble AS base

# Base system setup + shared dependencies
RUN <<EOF

set -eux
apt-get update
apt-get install -y --no-install-recommends \
	ca-certificates \
	sshpass \
	iptables \
	openssl \
	pigz \
	xz-utils \
	sudo \
	curl \
	wget \
	vim \
	lsb-release \
	gnupg \
	python3 \
	git \
	tmux \
	zsh \
	zsh-autosuggestions
rm -rf /var/lib/apt/lists/*

EOF

####################################
# Docker installation
####################################
ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client

COPY --from=docker:dind /usr/local/bin/ /usr/local/bin/
COPY --from=docker:dind /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

VOLUME /var/lib/docker


####################################
# uv installation
####################################
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="/usr/local/bin" sh

####################################
# SSH installation
####################################

COPY container_sshd.sh /usr/local/bin/container_sshd.sh
RUN bash <<EOF
#!/bin/bash

export USERNAME=root
export NEW_PASSWORD=admin
export SSHD_PORT=22

chmod +x /usr/local/bin/container_sshd.sh
/usr/local/bin/container_sshd.sh

EOF

####################################
# Define Installation Scripts
####################################

# install-sudo
RUN <<EOF
cat > /usr/local/bin/install-sudo << 'SCRIPT'
#!/bin/bash
# minimal script. for ubuntu-dind container, default username is ubuntu with 1000:1000.
useradd -u 1000 -g 1000 -m -s /bin/bash ubuntu
echo "ubuntu:admin" | chpasswd
adduser "ubuntu" sudo

SCRIPT
EOF

# install-gcloud script
RUN <<EOF
cat > /usr/local/bin/install-gcloud << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Installing Google Cloud CLI..."

if command -v gcloud >/dev/null 2>&1; then
    echo "Google Cloud CLI already installed"
    exit 0
fi

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list && \
apt-get update && \
apt-get install -y google-cloud-cli

echo "✅ Google Cloud CLI installed"
gcloud version
SCRIPT
EOF

# install-node script
RUN <<EOF
cat > /usr/local/bin/install-node << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Installing Node..."

if command -v node >/dev/null 2>&1; then
    echo "Node already installed"
    exit 0
fi

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 22

echo "✅ Node installed"
node --version
SCRIPT
EOF

# install-terraform script
RUN <<EOF
cat > /usr/local/bin/install-terraform << 'SCRIPT'
#!/bin/bash
set -euo pipefail

echo "Installing Terraform..."

if command -v terraform >/dev/null 2>&1; then
    echo "Terraform already installed"
    exit 0
fi

wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

echo "✅ Terraform installed"
terraform version
SCRIPT
EOF

# Make scripts executable in the base stage
RUN chmod +x /usr/local/bin/install-*

####################################
# Final setup
####################################
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]


####################################
# Full variant
####################################
FROM base AS full

# Execute the installation scripts that are already present from the base image
RUN find /usr/local/bin -name 'install-*' -type f -executable | \
	xargs -r -I{} bash -c '{}'


####################################
# Slim variant
####################################
FROM base AS slim
