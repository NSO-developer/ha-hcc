#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function on_leader() { printf "${PURPLE}On leader CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_leader_sh() { printf "${PURPLE}On leader: ${NC}$@\n"; ssh -l admin -p 22 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o LogLevel=ERROR "$1" "$2" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -p 22 -o LogLevel=ERROR "$1" "$2" ; }
function scp_node() { printf "${PURPLE}scp from: $1 to: $2${NC}\n"; scp -o LogLevel=ERROR "$1" "$2" ; }

NODES=( ${NODE1} ${NODE2} ${NODE3} )

set +u
source /nso-${NEW_NSO_VERSION}/ncsrc
set -u

printf "\n${PURPLE}##### Backup before upgrading NSO\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_sh $NODE '${NCS_DIR}/bin/ncs-backup'
done

LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"
printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "\n${PURPLE}##### The ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${GREEN}##### Upgrade the leader $CURRENT_LEADER packages and sync the packages to the followers\n${NC}"
cd /root/package-store
ncs-make-package --service-skeleton template --dest dummy-1.1 \
                 --no-test --root-container dummies dummy
rm -rf dummy-1.1/templates/*
sed -i -e "s/1.0/1.1/g" dummy-1.1/package-meta-data.xml
cp /root/manager-etc/yang/dummy.yang dummy-1.1/src/yang/dummy.yang
sed -i -e "s|// replace with your own stuff here|leaf description {type string;}|" dummy-1.1/src/yang/dummy.yang
make -C dummy-1.1/src clean all
tar cfz dummy-1.1.tar.gz dummy-1.1
rm -rf dummy-1.1

ncs-make-package --service-skeleton template --dest inert-1.0 --no-test --root-container inerts inert
rm -rf inert-1.0/templates/*
sed -i -e "s|uses ncs:service|//uses ncs:service|" inert-1.0/src/yang/inert.yang
sed -i -e "s|ncs:servicepoint|//ncs:servicepoint|" inert-1.0/src/yang/inert.yang
make -C inert-1.0/src clean all
tar cfz inert-1.0.tar.gz inert-1.0
rm -rf inert-1.0

# Can use the container shared volumes here, but if no containers and shared volumes, for example, use scp
scp_node "/root/package-store/dummy-1.1.tar.gz" "admin@$CURRENT_LEADER:/home/admin/etc/package-store/"
scp_node "/root/package-store/inert-1.0.tar.gz" "admin@$CURRENT_LEADER:/home/admin/etc/package-store/"

on_leader "software packages list"
on_leader "software packages fetch package-from-file /home/admin/etc/package-store/dummy-1.1.tar.gz"
on_leader "software packages fetch package-from-file /home/admin/etc/package-store/inert-1.0.tar.gz"
on_leader "software packages list"
on_leader "software packages install package inert-1.0"
on_leader "software packages install package dummy-1.1 replace-existing"
on_leader "software packages list"

on_leader "packages ha sync and-reload { wait-commit-queue-empty };software packages list"

set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to initialize. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n\n${PURPLE}##### Add some new config through the leader ${CURRENT_LEADER} node\n${NC}"
on_leader 'config; dummies dummy d1 description "hello world"; inerts inert i1 dummy 4.3.2.1; commit'

for NODE in "${NODES[@]}" ; do
    printf "\n${PURPLE}##### Show $NODE state (current leader: ${CURRENT_LEADER})\n${NC}"
    on_node $NODE "show ha-raft"
    on_node $NODE "show running-config dummies; show running-config inerts"
    on_node $NODE "software packages list"
    on_node $NODE "show packages package package-version"
done

printf "\n${GREEN}##### Done!\n${NC}"