#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function on_primary() { printf "${PURPLE}On primary CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o LogLevel=ERROR "$1" "$2" ; }

function on_primary_sh() { printf "${PURPLE}On primary: ${NC}$@\n"; ssh -l admin -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -o LogLevel=ERROR "$1" "$2" ; }

function on_primary_root() { printf "${PURPLE}On primary: ${NC}$@\n"; ssh -l root -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node_root() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l root -o LogLevel=ERROR "$1" "$2" ; }

function scp_node() { printf "${PURPLE}scp from: $1 to: $2${NC}\n"; scp -o LogLevel=ERROR "$1" "$2" ; }

function version_lt() { test "$(printf '%s\n' "$@" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(printf '%s\n' "$@" | sort -rV | head -n 1)" == "$1"; }

NSO55=5.5
NSO56=5.6

printf "\n${PURPLE}##### Start the rsyslog daemon and setup SSH\n${NC}"
/usr/sbin/rsyslogd

mkdir /root/.ssh
ssh-keygen -N "" -t ed25519 -m pem -f /root/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519.pub
chmod 600 /root/.ssh/id_ed25519
chmod 700 /root/.ssh

printf "\n\n${GREEN}#### A two node HA setup with one primary ${NODE1_NAME} and one secondary ${NODE2_NAME} node\n${NC}"
printf "\n${PURPLE}VIP address: ${NSO_VIP}\n${NC}"

set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1
do
  printf "${RED}#### Waiting for the ${NSO_VIP} VIP route to be initialized. Retry...\n${NC}"
done
set -e

while [[ "$(on_primary 'show high-availability status connected-slave | notab')" != *"${NODE2_NAME}"* ]] ; do
  printf "${RED}#### Waiting for the secondary node ${NODE2_NAME} to connect...\n${NC}"
  sleep 1
done

printf "\n${PURPLE}##### Initial high-availability config for both nodes\n${NC}"
on_primary "show running-config high-availability"

CID=$(on_primary "show high-availability status current-id")
CURRENT_VIP="${CID##* }"
printf "\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

printf "\n\n${GREEN}#### Test failover\n${NC}"
printf "\n${PURPLE}##### Add some dummy config to ${NODE1_NAME}, replicated to secondary ${NODE2_NAME}\n${NC}"
on_primary "config; dummies dummy d1 dummy 1.2.3.4; commit; do show high-availability | notab; show full-config dummies"
on_node ${NODE2_NAME} "show high-availability | notab | nomore; show running-config dummies"

printf "\n${PURPLE}##### Disable HA on the secondary node ${NODE2_NAME} to simulate secondary node failure, primary ${NODE1_NAME} will assume role none as all secondary nodes disconnected (see alarm), set ${NODE1_NAME} back to primary and enable the secondary again to re-connect to the primary node\n${NC}"
on_node ${NODE2_NAME} "high-availability disable"

while [[ "$(on_node ${NODE1_NAME} 'show high-availability status mode')" != *"none"* ]] ; do
  printf "${RED}#### Waiting for the primary node ${NODE1_NAME} to assume none role...\n${NC}"
  sleep 1
done

on_node ${NODE1_NAME} "show high-availability status; show alarms; high-availability be-master"
on_node ${NODE2_NAME} "high-availability enable"

while [[ "$(on_primary 'show high-availability status connected-slave | notab')" != *"${NODE2_NAME}"* ]] ; do
  printf "${RED}#### Waiting for the secondary node ${NODE2_NAME} to re-connect...\n${NC}"
  sleep 1
done

printf "\n${PURPLE}##### Disable HA on the primary ${NODE1_NAME} to make ${NODE2_NAME} failover to primary role\n${NC}"
on_node ${NODE1_NAME} "high-availability disable"

while [[ "$(on_node ${NODE2_NAME} 'show high-availability status mode')" != *"master"* ]] ; do
  printf "${RED}#### Waiting for ${NODE2_NAME} to fail reconnect to ${NODE1_NAME} and assume primary role...\n${NC}"
  sleep 1
done

printf "\n${PURPLE}##### Check that the current VIP node have switched to ${NODE2_NAME}\n${NC}"
while [[ "$(on_primary 'show high-availability status current-id')" != *"${NODE2_NAME}"* ]] ; do
  printf "${RED}#### Waiting for the ${NSO_VIP} to point to ${NODE2_NAME}...\n${NC}"
  sleep 1
done

CID=$(on_primary "show high-availability status current-id")
CURRENT_VIP="${CID##* }"
printf "\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

on_primary "show high-availability status"

printf "\n${PURPLE}##### Enable HA on ${NODE1_NAME} that will now assume secondary role\n${NC}"
on_node ${NODE1_NAME} "high-availability enable"

while [[ "$(on_node ${NODE1_NAME} 'show high-availability status mode')" != *"slave"* ]] ; do
  printf "${RED}#### Waiting for ${NODE1_NAME} to become secondary to ${NODE2_NAME}...\n${NC}"
  sleep 1
done

on_primary "show high-availability status"
on_node ${NODE1_NAME} "show high-availability status"

printf "\n${PURPLE}##### Role-revert the nodes back to start-up settings\n${NC}"

on_node ${NODE1_NAME} "high-availability disable"
on_node ${NODE2_NAME} "high-availability disable"
on_node ${NODE1_NAME} "high-availability enable"

while [[ "$(on_node ${NODE1_NAME} 'show high-availability status mode')" != *"master"* ]]; do
    printf "${RED}#### Waiting for ${NODE1_NAME} to revert to primary role...\n${NC}"
    sleep 1
done

on_node ${NODE2_NAME} "high-availability enable"

while [[ "$(on_node ${NODE2_NAME} 'show high-availability status mode')" != *"slave"* ]] ; do
  printf "${RED}#### Waiting for ${NODE2_NAME} to revert to secondary role for primary ${NODE1_NAME}...\n${NC}"
  sleep 1
done

CID=$(on_primary "show high-availability status current-id")
CURRENT_VIP="${CID##* }"
printf "\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

on_primary "show high-availability status; show running-config dummies"
on_node ${NODE2_NAME} "show high-availability status; show running-config dummies"

printf "\n\n${GREEN}##### Upgrade from NSO ${NSO_VERSION} to ${NEW_NSO_VERSION}\n${NC}"
printf "\n${PURPLE}##### Backup before upgrading NSO\n${NC}"
on_primary_sh '$NCS_DIR/bin/ncs-backup'
on_node_sh ${NODE2_NAME} '$NCS_DIR/bin/ncs-backup'

printf "${PURPLE}##### Install NSO ${NEW_NSO_VERSION} on both nodes\n${NC}"
scp_node /tmp/nso-${NEW_NSO_VERSION}.linux.x86_64.installer.bin root@${NSO_VIP}:/tmp/
scp_node /tmp/ncs-${NEW_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz admin@${NSO_VIP}:/${APP_NAME}/package-store/

on_primary_root 'chmod u+x /tmp/nso-$NEW_NSO_VERSION.linux.x86_64.installer.bin; /tmp/nso-$NEW_NSO_VERSION.linux.x86_64.installer.bin --system-install --run-as-user admin --non-interactive; chown admin:ncsadmin $NCS_ROOT_DIR; chown root $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper; chmod u+s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper; rm $NCS_DIR; ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR'

scp_node /tmp/nso-${NEW_NSO_VERSION}.linux.x86_64.installer.bin root@${NODE2_NAME}:/tmp/
scp_node /tmp/ncs-${NEW_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz admin@${NODE2_NAME}:/${APP_NAME}/package-store/

on_node_root ${NODE2_NAME} 'chmod u+x /tmp/nso-$NEW_NSO_VERSION.linux.x86_64.installer.bin; /tmp/nso-$NEW_NSO_VERSION.linux.x86_64.installer.bin --system-install --run-as-user admin --non-interactive; chown root $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper; chmod u+s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper; rm $NCS_DIR; ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR'

# NSO 5.5 removed the show-log-directory parameter.
if version_lt $NSO_VERSION $NSO55 && version_ge $NEW_NSO_VERSION $NSO55; then
    on_primary_sh 'sed -i.bak "s%<show-log-directory>./logs</show-log-directory>%%" $NCS_CONFIG_DIR/ncs.conf'
    on_node_sh ${NODE2_NAME} 'sed -i.bak "s%<show-log-directory>./logs</show-log-directory>%%" $NCS_CONFIG_DIR/ncs.conf'
fi

# NSO 5.6 removed the large-scale parameters
if version_lt $NSO_VERSION $NSO56 && version_ge $NEW_NSO_VERSION $NSO56
then
    on_primary_sh 'sed -i.bak "/<large-scale>/I,+7 d" $NCS_CONFIG_DIR/ncs.conf'
    on_node_sh ${NODE2_NAME} 'sed -i.bak "/<large-scale>/I,+7 d" $NCS_CONFIG_DIR/ncs.conf'
fi

printf "\n${PURPLE}##### Rebuild the primary ${NODE1_NAME} node packages in its package store for NSO ${NEW_NSO_VERSION}\n${NC}"
on_primary_sh 'source $NCS_DIR/ncsrc; cd /$APP_NAME; make rebuild-packages'

printf "\n${PURPLE}##### Apply a temporary privilege issue fix to the Tail-f HCC package\n${NC}"
on_primary_sh 'cd /$APP_NAME; make HCC_TARBALL_NAME="ncs-${NEW_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz" hcc-fix'

printf "\n${PURPLE}##### Replace the currently installed packages on the ${NODE1_NAME} node with the ones built for NSO ${NEW_NSO_VERSION}\n${NC}"
on_primary_sh 'rm $NCS_RUN_DIR/packages/* ; cp /$APP_NAME/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages ; cp /$APP_NAME/package-store/ncs-$NEW_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz $NCS_RUN_DIR/packages'

printf "\n${PURPLE}##### Disable primary node ${NODE1_NAME} high availability for secondary node ${NODE2_NAME} to automatically failover and assume primary role in read-only mode\n${NC}"
on_node ${NODE1_NAME} "high-availability disable; software packages list; show packages"

printf "\n${PURPLE}##### Upgrade the ${NODE1_NAME} node to $NEW_NSO_VERSION\n${NC}"
on_node_sh ${NODE1_NAME} '$NCS_DIR/bin/ncs --stop; $NCS_DIR/bin/ncs -c $NCS_CONFIG_DIR/ncs.conf --with-package-reload'

printf "\n${PURPLE}##### Disable high availability for the ${NODE2_NAME} node\n${NC}"
on_node ${NODE2_NAME} "high-availability disable; software packages list; show packages"

printf "\n${PURPLE}##### Enable high availability for the ${NODE1_NAME} node that will assume primary role\n${NC}"
on_node ${NODE1_NAME} "high-availability enable; software packages list; show packages"

printf "\n${PURPLE}##### Rebuild the secondary ${NODE2_NAME} node packages in its package store for NSO ${NEW_NSO_VERSION}\n${NC}"
on_node_sh ${NODE2_NAME} 'source $NCS_DIR/ncsrc; cd /$APP_NAME; make rebuild-packages'

printf "\n${PURPLE}##### Replace the currently installed packages on the ${NODE2_NAME} node with the ones built for NSO ${NEW_NSO_VERSION}\n${NC}"
on_node_sh ${NODE2_NAME} 'rm $NCS_RUN_DIR/packages/* ; cp /$APP_NAME/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages ; cp /$APP_NAME/package-store/ncs-$NEW_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz $NCS_RUN_DIR/packages'

printf "\n${PURPLE}##### Upgrade the ${NODE2_NAME} node to $NEW_NSO_VERSION\n${NC}"
on_node_sh ${NODE2_NAME} '$NCS_DIR/bin/ncs --stop; $NCS_DIR/bin/ncs -c $NCS_CONFIG_DIR/ncs.conf --with-package-reload'

while [[ "$(on_node ${NODE1_NAME} 'show high-availability status mode')" != *"master"* ]]; do
    printf "${RED}#### Waiting for ${NODE1_NAME} to assume primary role...\n${NC}"
    sleep 1
done

printf "\n${PURPLE}##### Enable high availability for the ${NODE2_NAME} node that will assume secondary role\n${NC}"
on_node ${NODE2_NAME} "high-availability enable; software packages list; show packages"

while [[ "$(on_node ${NODE2_NAME} 'show high-availability status mode')" != *"slave"* ]] ; do
  printf "${RED}#### Waiting for ${NODE2_NAME} to assume secondary role...\n${NC}"
  sleep 1
done

on_primary "show high-availability status; show running-config dummies"
on_node ${NODE2_NAME} "show high-availability status; show running-config dummies"

printf "\n\n${GREEN}##### Upgrade primary ${NODE1_NAME} node packages and sync the packages to the secondary ${NODE2_NAME} node\n${NC}"
on_primary "software packages list"
on_primary "software packages fetch package-from-file /${APP_NAME}/package-store/inert-1.0.tar.gz; software packages fetch package-from-file /${APP_NAME}/package-store/dummy-1.1.tar.gz"
on_primary "software packages list"
on_primary "software packages install package inert-1.0; software packages install package dummy-1.1 replace-existing"
on_primary "software packages list"
LID=$(on_primary "devices commit-queue add-lock sync")
LOCK_ID="${LID##* }"
on_primary "packages ha sync and-reload"
on_primary "devices commit-queue queue-item $LOCK_ID unlock"

printf "\n\n${PURPLE}##### Add some new config through the primary ${NODE1_NAME} node\n${NC}"
on_primary 'config; dummies dummy d1 description "hello world"; top; inerts inert i1 dummy 4.3.2.1; commit'

on_primary "show high-availability; show running-config dummies; show running-config inerts; software packages list; show packages package package-version"
on_node ${NODE2_NAME} "show high-availability; show running-config dummies; show running-config inerts; software packages list; show packages package package-version"

printf "\n${GREEN}##### Done!\n${NC}"
printf "\n${GREEN}##### Now run a Python RESTCONF variant of this demo\n${NC}"
python3 run_rc.py

printf "\n${PURPLE}Start forwarding port 18888 to the VIP port 8888\n${NC}"
socat TCP-LISTEN:18888,fork TCP:${NSO_VIP}:8888
