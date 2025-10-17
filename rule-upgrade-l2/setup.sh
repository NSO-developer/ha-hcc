#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NSO_VERSION="6.5.3"
NEW_NSO_VERSION="6.5.4"
NSO_ARCH="x86_64"
HCC_NSO_VERSION="6.5.3"
NEW_HCC_NSO_VERSION="6.5.4"
HCC_VERSION="6.0.6"
NEW_HCC_VERSION="6.0.6"

NODE1=paris1.fra
NODE2=paris2.fra
NODE1_IP="192.168.23.99"
NODE2_IP="192.168.23.98"
MANAGER_IP="192.168.23.2"
NSO_VIP="192.168.23.122"
SUBNET="192.168.23.0/24"
GATEWAY="192.168.23.1"

NCS_DIR="/opt/ncs/current"
NCS_ROOT_DIR="/opt/ncs"
NCS_RUN_DIR="/var/opt/ncs"
NCS_CONFIG_DIR="/etc/ncs"
NCS_LOG_DIR="/var/log/ncs"

printf "NODE1=$NODE1\nNODE2=$NODE2\n" > ./.env
printf "NSO_VERSION=$NSO_VERSION\nNSO_ARCH=$NSO_ARCH\nHCC_NSO_VERSION=$HCC_NSO_VERSION\nHCC_VERSION=$HCC_VERSION\n" >> ./.env
printf "NODE1_IP=$NODE1_IP\nNODE2_IP=$NODE2_IP\nNSO_VIP=$NSO_VIP\n" >> ./.env
printf "MANAGER_IP=$MANAGER_IP\nSUBNET=$SUBNET\nGATEWAY=$GATEWAY\n" >> ./.env
printf "NEW_NSO_VERSION=$NEW_NSO_VERSION\nNEW_HCC_NSO_VERSION=$NEW_HCC_NSO_VERSION\nNEW_HCC_VERSION=$NEW_HCC_VERSION\n" >> ./.env
printf "NCS_DIR=$NCS_DIR\nNCS_ROOT_DIR=$NCS_ROOT_DIR\nNCS_RUN_DIR=$NCS_RUN_DIR\nNCS_CONFIG_DIR=$NCS_CONFIG_DIR\nNCS_LOG_DIR=$NCS_LOG_DIR\n" >> ./.env

if [ -f manager-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz ] && [ -f manager-etc/ncs-$NEW_HCC_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz ]
then
    echo "Using:"
    echo "manager-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz"
    echo "as the new version: manager-etc/ncs-$NEW_HCC_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz"
else
    echo >&2 "This demo require that the Tail-f HCC packages has been placed in the manager-etc folder. E.g.:"
    echo >&2 "manager-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz"
    echo >&2 "manager-etc/ncs-$NEW_HCC_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -f manager-etc/nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin ] && [ -f manager-etc/nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin ]
then
    echo "Using:"
    echo "manager-etc/nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin"
    echo "manager-etc/nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin"
else
    echo >&2 "This demo require that the Tail-f HCC packages has been placed in the manager-etc folder. E.g.:"
    echo >&2 "manager-etc/nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin"
    echo >&2 "manager-etc/nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin"
    echo >&2 "Aborting..."
    exit 1
fi

printf "${GREEN}##### Reset the container setup\n${NC}"
docker compose --profile manager down -v
docker compose --profile nso down -v

docker compose build NODE-1 MANAGER

printf "${GREEN}##### Start the manager container\n${NC}"
docker compose --profile manager up --wait

printf "${GREEN}##### Start the NSO containers\n${NC}"
docker compose --profile nso up --wait

printf "\n${GREEN}##### Run a demo from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager /root/manager-etc/demo.sh

printf "\n${GREEN}##### Run an NSO upgrade from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager /root/manager-etc/upgrade_nso.sh

printf "\n${GREEN}##### Run a package version upgrade from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager /root/manager-etc/upgrade_packages.sh

printf "\n${GREEN}##### Run a Python demo from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager python3 /root/manager-etc/demo_rc.py

printf "\n${GREEN}##### Follow the NODE-1 NODE-2 MANAGER logs\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker compose logs --follow NODE-1 NODE-2 MANAGER
