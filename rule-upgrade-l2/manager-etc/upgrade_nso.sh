#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function on_primary() { printf "${PURPLE}On primary CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o ServerAliveInterval=1 -o ServerAliveCountMax=3 -o LogLevel=ERROR "$1" "$2" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -p 22 -o ServerAliveInterval=1 -o ServerAliveCountMax=3 -o LogLevel=ERROR "$1" "$2" ; }
function on_node_root() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -i /root/.ssh/upgrade-keys/id_ed25519 -l root -p 22 -o LogLevel=ERROR "$1" "$2" ; }
function scp_node() { printf "${PURPLE}scp from: $1 to: $2${NC}\n"; scp -o LogLevel=ERROR "$1" "$2" ; }

NODES=( ${NODE1} ${NODE2} )

CURRENT_ID=$(on_primary "show high-availability status current-id")
tmp="${CURRENT_ID##* }"
PRIMARY="${tmp::-1}"

printf "\n${GREEN}##### Current primary node: ${PURPLE}$PRIMARY\n${NC}"

printf "\n${GREEN}##### Upgrade from NSO ${NSO_VERSION} to ${NEW_NSO_VERSION}\n${NC}"
printf "\n${PURPLE}##### Install the new NSO version on the manager for rebuilding packages\n${NC}"
if ! [ -d /nso-${NEW_NSO_VERSION} ] ; then
    cp manager-etc/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin /tmp/
    chmod u+x /tmp/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin
    /tmp/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin /nso-${NEW_NSO_VERSION}
fi
set +u
source /nso-${NEW_NSO_VERSION}/ncsrc
set -u

printf "\n${PURPLE}##### Backup before upgrading NSO\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_sh $NODE '${NCS_DIR}/bin/ncs-backup'
done

printf "\n${PURPLE}##### Delete the old packages in the nodes package store\n${NC}"
for NODE in "${NODES[@]}" ; do
    rm -f /$NODE/package-store/*
done

printf "\n${PURPLE}##### Upgrade the HCC package on all nodes package store\n${NC}"
cp /root/manager-etc/ncs-${NEW_HCC_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz /root/package-store
for NODE in "${NODES[@]}" ; do
    scp_node "/root/package-store/ncs-${NEW_HCC_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz" "admin@$NODE:/home/admin/etc/package-store/tailf-hcc.tar.gz"
done

printf "\n${PURPLE}##### Rebuild and upgrade the dummy-1.0 and token-1.0 packages for all nodes\n${NC}"
tar xvfz /root/package-store/dummy-1.0.tar.gz
make -C dummy-1.0/src/ clean all
tar cvfz /root/package-store/dummy-1.0.tar.gz dummy-1.0
rm -rf dummy-1.0
tar xvfz /root/package-store/token-1.0.tar.gz
make -C token-1.0/src/ clean all
tar cvfz /root/package-store/token-1.0.tar.gz token-1.0
rm -rf token-1.0


for NODE in "${NODES[@]}" ; do
    scp_node "/root/package-store/dummy-1.0.tar.gz" "admin@$NODE:/home/admin/etc/package-store/"
    scp_node "/root/package-store/token-1.0.tar.gz" "admin@$NODE:/home/admin/etc/package-store/"
done

printf "\n${PURPLE}##### Copy the new NSO ${NEW_NSO_VERSION} version to all nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    scp_node "manager-etc/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin" "admin@$NODE:/tmp/"
done

printf "\n${PURPLE}##### Install NSO ${NEW_NSO_VERSION} on all nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_root $NODE 'chmod u+x /tmp/nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin &&
/tmp/nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin --system-install --run-as-user admin --non-interactive &&
chown root $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper &&
chmod u+s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper'
done

printf "\n${PURPLE}##### Disable primary node ${NODE1} high availability for secondary node ${NODE2} to automatically failover and assume primary role in read-only mode\n${NC}"
on_node ${NODE1} "high-availability disable; software packages list; show packages"

set +e
printf "\n${PURPLE}##### Upgrade the ${NODE1} node to ${NEW_NSO_VERSION}\n${NC}"
on_node_sh ${NODE1} 'touch $NCS_RUN_DIR/upgrade &&
touch $NCS_RUN_DIR/package_reload &&
$NCS_DIR/bin/ncs --stop'
set -e

until on_node_sh ${NODE1} '[ -f $NCS_RUN_DIR/upgrade ]' ; do
    printf "${RED}##### Waiting for ${NODE1} to come back up. Retry...\n${NC}"
    sleep .5
done

printf "\n${PURPLE}##### Replace the currently installed packages on the ${NODE1} node with the ones built for NSO ${NEW_NSO_VERSION} and switch to ${NEW_NSO_VERSION}\n${NC}"
on_node_sh ${NODE1} 'rm $NCS_RUN_DIR/packages/* &&
cp /home/admin/etc/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages &&
cp /home/admin/etc/package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages &&
cp /home/admin/etc/package-store/tailf-hcc.tar.gz $NCS_RUN_DIR/packages &&
rm $NCS_DIR &&
ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR'

set +e
while [[ "$(on_node ${NODE2} 'high-availability status mode')" != *"primary"* ]] ; do
  printf "${RED}#### Waiting for ${NODE2} to timeout reconnecting to ${NODE1} and revert to primary role...\n${NC}"
  sleep 1
done
set -e

printf "\n${GREEN}##### Current primary node: ${PURPLE}${NODE2}\n${NC}"

printf "\n${PURPLE}##### Start ${NODE1}\n${NC}"
on_node_sh ${NODE1} 'rm -f  $NCS_RUN_DIR/upgrade'

printf "\n${PURPLE}##### Disable high availability for the ${NODE2} node\n${NC}"
on_node ${NODE2} "high-availability disable; software packages list; show packages"

set +e
until on_node ${NODE1} "show ncs-state version" = "ncs-state version ${NEW_NSO_VERSION}" ; do
    printf "${RED}##### Waiting for NSO on ${NODE1} to come back up. Retry...\n${NC}"
    sleep 1
done
set -e
on_node_sh ${NODE1} 'rm -f $NCS_RUN_DIR/package_reload'

printf "\n${PURPLE}##### Enable high availability for the ${NODE1} node that will assume primary role\n${NC}"
on_node ${NODE1} "high-availability enable; software packages list; show packages"

printf "\n${PURPLE}##### Upgrade the ${NODE2} node to ${NEW_NSO_VERSION}\n${NC}"
set +e
on_node_sh ${NODE2} 'touch $NCS_RUN_DIR/upgrade &&
touch $NCS_RUN_DIR/package_reload &&
$NCS_DIR/bin/ncs --stop'
set -e

until on_node_sh ${NODE2} '[ -f $NCS_RUN_DIR/upgrade ]' ; do
    printf "${RED}##### Waiting for ${NODE2} to come back up. Retry...\n${NC}"
    sleep .5
done

printf "\n${PURPLE}##### Replace the currently installed packages on the ${NODE2} node with the ones built for NSO ${NEW_NSO_VERSION} and switch to ${NEW_NSO_VERSION}\n${NC}"
on_node_sh ${NODE2} 'rm $NCS_RUN_DIR/packages/* &&
cp /home/admin/etc/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages &&
cp /home/admin/etc/package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages &&
cp /home/admin/etc/package-store/tailf-hcc.tar.gz $NCS_RUN_DIR/packages &&
rm $NCS_DIR &&
ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR &&
rm -f  $NCS_RUN_DIR/upgrade'

while [[ "$(on_node ${NODE1} 'show high-availability status mode')" != *"primary"* ]]; do
    printf "${RED}#### Waiting for ${NODE1} to assume primary role...\n${NC}"
    sleep 1
done

set +e
until on_node ${NODE2} "show ncs-state version" = "ncs-state version ${NEW_NSO_VERSION}" ; do
    printf "${RED}##### Waiting for NSO on ${NODE2} to come back up. Retry...\n${NC}"
    sleep 1
done
set -e
on_node_sh ${NODE2} 'rm -f $NCS_RUN_DIR/package_reload'

printf "\n${PURPLE}##### Enable high availability for the ${NODE2} node that will assume secondary role\n${NC}"
on_node ${NODE} "high-availability enable; software packages list; show packages"

while [[ "$(on_node ${NODE2} 'show high-availability status mode')" != *"secondary"* ]] ; do
  printf "${RED}#### Waiting for ${NODE2} to assume secondary role...\n${NC}"
  sleep 1
done

on_primary "show high-availability status; show running-config dummies"
on_node ${NODE} "show high-availability status; show running-config dummies"

printf "\n${PURPLE}The ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${GREEN}##### Done!\n${NC}"