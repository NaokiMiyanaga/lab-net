FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y frr frr-snmp snmp snmpd iproute2 iputils-ping procps net-tools &&       rm -rf /var/lib/apt/lists/*

COPY init/ /init/
RUN set -eux; \
    find /init -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; ; \
    chmod +x /init/*.sh