# https://github.com/docker-library/docker/issues/306#issuecomment-815338333

FROM ubuntu:latest AS base

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
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

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

# Minimal script to create or update a user with specific UID/GID and sudo access.
# Intended to be run as root inside a container.
# If a user with the target UID exists, it updates that user.
# If not, it creates a new user named 'dev'.

# --- Configuration ---
DEFAULT_USER_IF_NEW="dev"
DEFAULT_PASSWORD="admin" # WARNING: Hardcoded password - not for production!
SUDO_GROUP="sudo"
DEFAULT_SHELL="/bin/bash"
# ---------------------

# --- Argument Check ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <target_uid> <target_gid>" >&2
    exit 1
fi

TARGET_UID="$1"
TARGET_GID="$2"
TARGET_USER="" # Will be determined based on existence

# --- Step 0: Check if default shell exists ---
if [ ! -x "$DEFAULT_SHELL" ]; then
    echo "Error: Default shell '$DEFAULT_SHELL' does not exist or is not executable." >&2
    exit 1
fi

# --- Step 1: Ensure the target group exists ---
# Check if a group with the target GID already exists
if ! getent group "$TARGET_GID" > /dev/null; then
    groupadd -g "$TARGET_GID" "group_$TARGET_GID"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create group with GID $TARGET_GID." >&2
        exit 1
    fi
fi

# --- Check if user with TARGET_UID already exists ---
USER_ENTRY=$(getent passwd "$TARGET_UID")

if [ -n "$USER_ENTRY" ]; then
    # --- User exists: Update in place ---
    TARGET_USER=$(echo "$USER_ENTRY" | cut -d: -f1) # Extract existing username
    echo "User with UID $TARGET_UID ('$TARGET_USER') already exists. Updating..."

    # Update primary GID if different
    CURRENT_GID=$(echo "$USER_ENTRY" | cut -d: -f4)
    if [ "$CURRENT_GID" != "$TARGET_GID" ]; then
        usermod -g "$TARGET_GID" "$TARGET_USER"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to update primary GID for user '$TARGET_USER'." >&2
            exit 1
        fi
    fi

    # Update default shell if different
    CURRENT_SHELL=$(echo "$USER_ENTRY" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "$DEFAULT_SHELL" ]; then
         usermod -s "$DEFAULT_SHELL" "$TARGET_USER"
         if [ $? -ne 0 ]; then
            echo "Error: Failed to update default shell for user '$TARGET_USER'." >&2
            exit 1
        fi
    fi

    # Set the user's password
    echo "$TARGET_USER:$DEFAULT_PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set password for user '$TARGET_USER'." >&2
        exit 1
    fi

    # Add the user to the sudo group (adduser is idempotent for adding to group)
    if ! getent group "$SUDO_GROUP" > /dev/null; then
        echo "Warning: '$SUDO_GROUP' group does not exist. Cannot add user to sudo." >&2
    else
        adduser "$TARGET_USER" "$SUDO_GROUP"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add user '$TARGET_USER' to group '$SUDO_GROUP'." >&2
            exit 1
        fi
    fi

    echo "User '$TARGET_USER' (UID $TARGET_UID, GID $TARGET_GID) updated and added to sudo."

else
    # --- User does not exist: Create new user ---
    TARGET_USER="$DEFAULT_USER_IF_NEW"
    echo "User with UID $TARGET_UID does not exist. Creating new user '$TARGET_USER'..."

    # Create the user with specified UID, GID, and Shell
    useradd -u "$TARGET_UID" -g "$TARGET_GID" -m -s "$DEFAULT_SHELL" "$TARGET_USER"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create user '$TARGET_USER'." >&2
        exit 1
    fi

    # Set the user's password
    echo "$TARGET_USER:$DEFAULT_PASSWORD" | chpasswd
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set password for user '$TARGET_USER'." >&2
        # Optional: Clean up user if password fails
        # userdel -r "$TARGET_USER"
        exit 1
    fi

    # Add the user to the sudo group
    if ! getent group "$SUDO_GROUP" > /dev/null; then
        echo "Warning: '$SUDO_GROUP' group does not exist. Cannot add user to sudo." >&2
    else
        adduser "$TARGET_USER" "$SUDO_GROUP"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to add user '$TARGET_USER' to group '$SUDO_GROUP'." >&2
            # Optional: Decide on cleanup
            exit 1
        fi
    fi

    echo "User '$TARGET_USER' (UID $TARGET_UID, GID $TARGET_GID) created and added to sudo."
fi

exit 0

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
