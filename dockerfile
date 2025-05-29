FROM ubuntu:latest

# https://github.com/docker-library/docker/issues/306#issuecomment-815338333
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		iptables \
		openssl \
		pigz \
		xz-utils \
		curl \
		python3.12 \
	; \
	rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

ENV DOCKER_TLS_CERTDIR=/certs
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client

COPY --from=docker:dind /usr/local/bin/ /usr/local/bin/
COPY --from=docker:dind /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

VOLUME /var/lib/docker

RUN rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["dockerd-entrypoint.sh"]
CMD []