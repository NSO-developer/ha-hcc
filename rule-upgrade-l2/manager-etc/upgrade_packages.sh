#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function on_primary() { printf "${PURPLE}On primary CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_primary_sh() { printf "${PURPLE}On primary: ${NC}$@\n"; ssh -l admin -p 22 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o LogLevel=ERROR "$1" "$2" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -p 22 -o LogLevel=ERROR "$1" "$2" ; }
function scp_node() { printf "${PURPLE}scp from: $1 to: $2${NC}\n"; scp -o LogLevel=ERROR "$1" "$2" ; }

NODES=( ${NODE1} ${NODE2} )

set +u
source /nso-${NEW_NSO_VERSION}/ncsrc
set -u

CURRENT_ID=$(on_primary "show high-availability status current-id")
tmp="${CURRENT_ID##* }"
PRIMARY="${tmp::-1}"
printf "\n${GREEN}##### Current primary node: ${PURPLE}$PRIMARY\n${NC}"

printf "\n${PURPLE}##### Backup before upgrading NSO\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_sh $NODE '${NCS_DIR}/bin/ncs-backup'
done

printf "\n${PURPLE}##### The ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${GREEN}##### Upgrade the primary $PRIMARY packages and sync the packages to the secondary\n${NC}"
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
scp_node "/root/package-store/dummy-1.1.tar.gz" "admin@$PRIMARY:/home/admin/etc/package-store/"
scp_node "/root/package-store/inert-1.0.tar.gz" "admin@$PRIMARY:/home/admin/etc/package-store/"

on_primary "software packages list"
on_primary "software packages fetch package-from-file /home/admin/etc/package-store/dummy-1.1.tar.gz"
on_primary "software packages fetch package-from-file /home/admin/etc/package-store/inert-1.0.tar.gz"
on_primary "software packages list"
on_primary "software packages install package inert-1.0"
on_primary "software packages install package dummy-1.1 replace-existing"
on_primary "software packages list"

on_primary "packages ha sync and-reload { wait-commit-queue-empty }"
on_primary "software packages list"

set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to initialize. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n${PURPLE}##### Add some new config through the primary ${PRIMARY} node\n${NC}"
on_primary 'config; dummies dummy d1 description "hello world"; inerts inert i1 dummy 4.3.2.1; commit'

for NODE in "${NODES[@]}" ; do
    printf "\n${PURPLE}##### Show $NODE state (current primary: ${PRIMARY})\n${NC}"
    on_node $NODE "show high-availability"
    on_node $NODE "show running-config dummies; show running-config inerts"
    on_node $NODE "software packages list"
    on_node $NODE "show packages package package-version"
done

printf "\n${GREEN}##### Done!\n${NC}"