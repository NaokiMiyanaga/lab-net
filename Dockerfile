FROM debian:11

RUN apt-get update && \
    apt-get install -y frr snmpd snmp libsnmp-dev iproute2 iputils-ping && \
    rm -rf /var/lib/apt/lists/*

COPY init /init
WORKDIR /init

CMD ["bash", "/init/r1-init.sh"]
