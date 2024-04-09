#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color
NODES=( ${NODE1} ${NODE2} )

printf "${GREEN}##### Manager setup\n${NC}"

printf "\n${PURPLE}##### Start the rsyslog daemon\n${NC}"
/usr/sbin/rsyslogd

printf "\n${PURPLE}##### Generate the ncs.crypto_keys file\n${NC}"
function gen_random() { dd if=/dev/urandom bs=1 count=$1 2>/dev/null | xxd -ps; }
echo "DES3CBC_KEY1=$(gen_random 8)" > /root/ncs.crypto_keys
chmod 640 /root/ncs.crypto_keys
echo "DES3CBC_KEY2=$(gen_random 8)" >> /root/ncs.crypto_keys
echo "DES3CBC_KEY3=$(gen_random 8)" >> /root/ncs.crypto_keys
echo "AESCFB128_KEY=$(gen_random 16)" >> /root/ncs.crypto_keys
echo "AES256CFB128_KEY=$(gen_random 16)$(gen_random 16)" >> /root/ncs.crypto_keys

printf "${PURPLE}##### Create the nodes host keys and copy the public key to the manager node known_hosts file\n${NC}"
mkdir /root/.ssh
touch /root/.ssh/known_hosts
for NODE in "${NODES[@]}" ; do
    ssh-keygen -N "" -t ed25519 -m pem -f /root/${NODE}_ssh_host_ed25519_key
    HOST_KEY=$(cat /root/${NODE}_ssh_host_ed25519_key.pub | cut -d ' ' -f1-2)
    echo "$NODE $HOST_KEY" >> /root/.ssh/known_hosts
    echo "[$NODE]:2024 $HOST_KEY" >> /root/.ssh/known_hosts
    echo "${NSO_VIP} $HOST_KEY" >> /root/.ssh/known_hosts
    echo "[${NSO_VIP}]:2024 $HOST_KEY" >> /root/.ssh/known_hosts
done
ssh-keygen -Hf /root/.ssh/known_hosts
rm /root/.ssh/known_hosts.old

printf "${PURPLE}##### Generate the manager keys for the nodes admin and oper users\n${NC}"
ssh-keygen -N "" -t ed25519 -m pem -f /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519.pub /root/.ssh/id_ed25519
chmod 750 /root/.ssh

printf "${PURPLE}##### Generate the manager keys for the nodes root user\n${NC}"
mkdir -p /root/.ssh/upgrade-keys
ssh-keygen -N "" -t ed25519 -m pem -f /root/.ssh/upgrade-keys/id_ed25519
chmod 600 /root/.ssh/id_ed25519.pub /root/.ssh/upgrade-keys/id_ed25519
chmod 750 /root/.ssh/upgrade-keys

printf "${PURPLE}##### Copy the HCC package(s) to the manager package-store and NSO node where HA raft is initialized\n${NC}"
mkdir -p /root/package-store
cp /root/manager-etc/ncs-*-tailf-hcc-*.tar.gz /root/package-store/

printf "${PURPLE}##### Create and build dummy and RESTCONF token store packages and copy to the NSO node where HA raft is initialized\n${NC}"
set +u
source /nso-${NSO_VERSION}/ncsrc
set -u

cd /root/package-store
ncs-make-package --service-skeleton template \
                    --dest dummy-1.0 \
                    --no-test --root-container dummies dummy
rm -rf dummy-1.0/templates/* ;
cp /root/manager-etc/yang/dummy.yang dummy-1.0/src/yang/dummy.yang
make -C dummy-1.0/src clean all
tar cfz dummy-1.0.tar.gz dummy-1.0
rm -rf dummy-1.0

ncs-make-package --service-skeleton template \
                    --dest token-1.0 \
                    --no-test --root-container tokens token
rm -rf token-1.0/templates/*
cp /root/manager-etc/yang/token.yang token-1.0/src/yang/token.yang
make -C token-1.0/src clean all
tar cfz token-1.0.tar.gz token-1.0
rm -rf token-1.0

printf "${PURPLE}##### Update ncs.conf with HA Raft node config and add the host key and managers authorized public key to the nodes}\n${NC}"
for NODE in "${NODES[@]}" ; do
    mkdir /$NODE/package-store
    cp dummy-1.0.tar.gz /$NODE/package-store/
    cp token-1.0.tar.gz /$NODE/package-store/
    cp /root/package-store/ncs-*-tailf-hcc-*.tar.gz /$NODE/package-store/tailf-hcc.tar.gz

    cp /root/${NODE}_ssh_host_ed25519_key /$NODE/ssh_host_ed25519_key
    cp /root/${NODE}_ssh_host_ed25519_key.pub /$NODE/ssh_host_ed25519_key.pub
    cat /root/.ssh/id_ed25519.pub > /$NODE/authorized_keys
    cp /root/.ssh/upgrade-keys/id_ed25519.pub /$NODE/upgrade_key

    cat /root/manager-etc/ncs.conf.in > /$NODE/ncs.conf
    cp /root/ncs.crypto_keys /$NODE/ncs.crypto_keys
    # Done with the node host keys
    rm /root/${NODE}_ssh_host_ed25519_key*
done
# Done with NSO crypto keys on the manager
rm /root/ncs.crypto_keys

printf "${GREEN}##### Manager setup done!\n${NC}"

