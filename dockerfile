# https://github.com/docker-library/docker/issues/306#issuecomment-815338333

FROM ubuntu:latest

# Base system setup + shared dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		iptables \
		openssl \
		pigz \
		xz-utils \
		curl \
		wget \
		lsb-release \
		gnupg \
		python3 \
		git \
		tmux \
		zsh \
		zsh-autosuggestions \
	; \
	rm -rf /var/lib/apt/lists/*

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
# Google Cloud CLI installation
####################################
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
	| gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
	echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
	> /etc/apt/sources.list.d/google-cloud-sdk.list && \
	apt-get update && \
	apt-get install -y google-cloud-cli && \
	rm -rf /var/lib/apt/lists/*

####################################
# Node.js (nvm) installation
####################################
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
	export NVM_DIR="$HOME/.nvm" && \
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && \
	[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" && \
	nvm install 22
	# nvm install 22 && \
	# echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc && \
	# echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.zshrc && \
	# echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.zshrc

####################################
# Terraform installation
####################################
RUN wget -O- https://apt.releases.hashicorp.com/gpg | \
	gpg --dearmor | \
	tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null && \
	echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
		https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
	tee /etc/apt/sources.list.d/hashicorp.list && \
	apt-get update && \
	apt-get install -y terraform && \
	rm -rf /var/lib/apt/lists/*

####################################
# SSH instal
####################################

COPY container_sshd.sh /usr/local/bin/container_sshd.sh
RUN chmod +x /usr/local/bin/container_sshd.sh && \
	USERNAME=root \
	NEW_PASSWORD=admin \
	SSHD_PORT=22 \
	/usr/local/bin/container_sshd.sh

####################################
# Final setup
####################################
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]