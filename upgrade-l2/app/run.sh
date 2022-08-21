#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

openssl rand -base64 32 > /root/ha_token
chmod 600 /root/ha_token

ssh-keygen -N "" -t ed25519 -m pem -f /etc/ssh/ssh_host_ed25519_key
chmod 600 /etc/ssh/ssh_host_ed25519_key.pub
chmod 600 /etc/ssh/ssh_host_ed25519_key

ssh-keygen -N "" -t ed25519 -m pem -f ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key
chmod 660 ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key.pub
chmod 660 ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key
chown -Rh admin:ncsadmin ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key*

ssh-keygen -N "" -t ed25519 -m pem -f /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519.pub
chmod 600 /root/.ssh/id_ed25519

ssh-keygen -N "" -t ed25519 -m pem -f /home/oper/.ssh/id_ed25519
chmod 644 /home/oper/.ssh/id_ed25519.pub
chmod 644 /home/oper/.ssh/id_ed25519
chown -Rh oper:ncsoper /home/oper/.ssh

ssh-keygen -N "" -t ed25519 -m pem -f /home/admin/.ssh/id_ed25519
chmod 640 /home/admin/.ssh/id_ed25519.pub
chmod 640 /home/admin/.ssh/id_ed25519
chown -Rh admin:ncsadmin /home/admin/.ssh

env | grep _ >> /root/.pam_environment
env | grep _ >> /home/admin/.pam_environment

printf "\n${PURPLE}##### Start the SSH daemon\n${NC}"
/usr/sbin/sshd

NODE_NAME=$(uname -n)

while [[ ( $(wc -l /home/admin/.ssh/authorized_keys) < 1 ) ]]; do
  echo "Waiting for authorized keys, host keys, and HA token to be configured on all nodes in the HA group by the manager"
  sleep 1
done

HA_TOKEN=$(head -n 1 /root/ha_token)

printf "\n${PURPLE}##### Apply a temporary privilege issue fix to the Tail-f HCC package\n${NC}"
make HCC_TARBALL_NAME="ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz" hcc-fix

printf "\n${PURPLE}##### Reset, setup, start NSO, and enable HA assuming start-up settings\n${NC}"
make stop &> /dev/null
make clean
runuser -m -u admin -g ncsadmin -- make -C /${APP_NAME} NODE_IP=${NODE_IP} HA_TOKEN=$HA_TOKEN all
cp package-store/dummy-1.0.tar.gz ${NCS_RUN_DIR}/packages
cp package-store/ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz ${NCS_RUN_DIR}/packages
runuser -m -u admin -g ncsadmin -- make start

ncs_cmd -u admin -g ncsadmin -o -c 'maction "/high-availability/enable"'

tail -F ${NCS_LOG_DIR}/devel.log
