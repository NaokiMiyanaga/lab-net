FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update &&       apt-get install -y         frr frr-snmp snmp snmpd iproute2 iputils-ping procps net-tools &&       rm -rf /var/lib/apt/lists/*

# Copy init scripts and shared config
COPY init/ /init/
RUN chmod +x /init/*.sh
