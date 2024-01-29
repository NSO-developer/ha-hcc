#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function version_lt() { test "$(printf '%s\n' "$@" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(printf '%s\n' "$@" | sort -rV | head -n 1)" == "$1"; }
NSO60=6.0
HCC501=5.0.1

# NSO 6 use primary secondary instead of master slave
if version_ge ${NSO_VERSION} $NSO60; then
  PRIMARY="primary"
  SECONDARY="secondary"
else
  PRIMARY="master"
  SECONDARY="slave"
fi

openssl rand -base64 32 > /home/admin/ha_token
chmod 600 /home/admin/ha_token
chown admin:ncsadmin /home/admin/ha_token

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

env /bin/bash -o posix -c 'export -p' >> /root/.bash_profile
env /bin/bash -o posix -c 'export -p' >> /home/admin/.bash_profile
env | grep _ >> /root/.pam_environment
env | grep _ >> /home/admin/.pam_environment
env | grep _ >> /root/.ssh/environment
env | grep _ >> /home/admin/.ssh/environment

printf "\n${PURPLE}##### Start the SSH and rsyslog daemons\n${NC}"
/usr/sbin/sshd
/usr/sbin/rsyslogd

while [[ ( $(wc -l /home/admin/.ssh/authorized_keys) < 1 ) ]]; do
  echo "Waiting for authorized keys, host keys, and HA token to be configured on all nodes in the HA group by the manager"
  sleep 1
done

if version_lt ${HCC_VERSION} $HCC501; then
  printf "\n${PURPLE}##### Apply a privilege issue fix to the Tail-f HCC package\n${NC}"
  make HCC_TARBALL_NAME="ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz" hcc-fix
fi

printf "\n${PURPLE}##### Reset, setup, start NSO, and enable HA assuming start-up settings\n${NC}"
make stop &> /dev/null
make clean
runuser -m -u admin -g ncsadmin -- make -C /${APP_NAME} NSO_VIP_NAME=${NSO_VIP_NAME} NODE_IP=${NODE_IP} HA_TOKEN=$(head -n 1 /home/admin/ha_token) PRIMARY=$PRIMARY SECONDARY=$SECONDARY all
cp package-store/dummy-1.0.tar.gz ${NCS_RUN_DIR}/packages
cp package-store/ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz ${NCS_RUN_DIR}/packages
runuser -m -u admin -g ncsadmin -- make start

ncs_cmd -u admin -g ncsadmin -o -c 'maction "/high-availability/enable"'

tail -F /var/log/daemon.log
