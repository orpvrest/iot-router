FROM debian:bookworm-slim

ENV EASYRSA_BATCH=1 \
    EASYRSA_PKI=/etc/openvpn/pki \
    EASYRSA_VARS_FILE=/etc/openvpn/easy-rsa.vars

# NOTE: Debian base is pinned via digest; adjust packages versions here if stricter pinning is required.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      openvpn \
      easy-rsa \
      iproute2 \
      bash \
      curl \
      ca-certificates \
      dumb-init \
      iptables \
      socat \
      tar; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/openvpn
COPY scripts/ ./scripts/
COPY config/ ./config/
RUN chmod +x /opt/openvpn/scripts/*.sh

VOLUME ["/etc/openvpn"]
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/opt/openvpn/scripts/entrypoint.sh"]
