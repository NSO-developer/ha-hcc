#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
NODES=( ${NODE1} ${NODE2} ${NODE3} )

printf "${GREEN}##### Demo setup\n${NC}"

printf "\n${PURPLE}##### Start the rsyslog daemon on the manager node\n${NC}"
/usr/sbin/rsyslogd

. /root/raft-etc/gen_tls_certs.sh
printf "${GREEN}##### Generate TLS certificates\n${NC}"
generate_tls_certificates

printf "\n${PURPLE}##### Generate the ncs.crypto_keys file\n${NC}"
function gen_random() { dd if=/dev/urandom bs=1 count=$1 2>/dev/null | xxd -ps; }
echo "DES3CBC_KEY1=$(gen_random 8)" > /root/ncs.crypto_keys
chmod 640 /root/ncs.crypto_keys
echo "DES3CBC_KEY2=$(gen_random 8)" >> /root/ncs.crypto_keys
echo "DES3CBC_KEY3=$(gen_random 8)" >> /root/ncs.crypto_keys
echo "AESCFB128_KEY=$(gen_random 16)" >> /root/ncs.crypto_keys
echo "AES256CFB128_KEY=$(gen_random 16)$(gen_random 16)" >> /root/ncs.crypto_keys

printf "${PURPLE}##### Create the nodes host keys and copy the public key to the manager node known_hosts file\n${NC}"
ssh-keygen -N "" -t ed25519 -m pem -f /root/ssh_host_ed25519_key
for NODE in "${NODES[@]}" ; do
    mkdir -p /$NODE/etc/ssh
    cp /root/ssh_host_ed25519_key* /$NODE/etc/ssh/
done
HOST_KEY=$(cat /root/ssh_host_ed25519_key.pub | cut -d ' ' -f1-2)
rm /root/ssh_host_ed25519_key*
mkdir -p /root/.ssh
touch /root/.ssh/known_hosts
HOSTS=( ${NODE1} ${NODE2} ${NODE3} ${NSO_VIP} )
for HOST in "${HOSTS[@]}" ; do
    echo "$HOST $HOST_KEY" >> /root/.ssh/known_hosts
    echo "[$HOST]:2024 $HOST_KEY" >> /root/.ssh/known_hosts
done
ssh-keygen -Hf /root/.ssh/known_hosts
rm /root/.ssh/known_hosts.old

printf "\n${PURPLE}##### Generate the manager's SSH keys\n${NC}"
ssh-keygen -N "" -t ed25519 -m pem -f /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519.pub /root/.ssh/id_ed25519
chmod 750 /root/.ssh

printf "${GREEN}##### Update ncs.conf with HA Raft node config and add the managers authorized public key to ${NODE1} ${NODE2} ${NODE3}\n${NC}"
for NODE in "${NODES[@]}" ; do
    sed -e "s/CLUSTER_NAME/${CLUSTER}/" \
        -e "s/NODE_NAME/$NODE/g" \
        -e "s/SEED_NODE1/${NODE1}/" \
        -e "s/SEED_NODE2/${NODE2}/" \
        -e "s/SEED_NODE3/${NODE3}/" \
        /root/raft-etc/ncs.conf.in > /$NODE/etc/ncs.conf

    cat /root/.ssh/id_ed25519.pub > /$NODE/authorized_keys
    cp /root/ncs.crypto_keys /$NODE/etc/ncs.crypto_keys
done
# Done with the NSO crypto keys on the manager
rm /root/ncs.crypto_keys

printf "${GREEN}##### Copy the HCC package to the NSO node where HA raft is initialized\n${NC}"
mkdir -p /${NODE1}/run/packages
cp /root/raft-etc/ncs-*-tailf-hcc-*.tar.gz /${NODE1}/run/packages/tailf-hcc.tar.gz
