#!/bin/bash
FRR_MODULE_DIR=/usr/lib/aarch64-linux-gnu/frr/modules

mkdir -p /var/agentx /var/run/agentx
ln -sfn /var/agentx /var/run/agentx
chown -R Debian-snmp:Debian-snmp /var/agentx
chmod 0777 /var/agentx

cp /init/common-snmpd.conf /etc/snmp/snmpd.conf
pkill -x snmpd || true
sleep 1
snmpd -C -c /etc/snmp/snmpd.conf -f -Lo &

/usr/lib/frr/zebra --moduledir $FRR_MODULE_DIR -d -A 127.0.0.1 -M zebra_snmp
/usr/lib/frr/bgpd  --moduledir $FRR_MODULE_DIR -d -A 127.0.0.1 -M bgpd_snmp

tail -f /dev/null
