#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NSO_VERSION="6.6.2"
HCC_NSO_VERSION="6.6"
HCC_VERSION="6.0.7"

NODE1=paris1.fra
NODE2=paris2.fra
NODE1_IP="192.168.23.99"
NODE2_IP="192.168.23.98"
MANAGER_IP="192.168.23.2"
NSO_VIP="192.168.23.122"
SUBNET="192.168.23.0/24"
GATEWAY="192.168.23.1"

printf "NODE1=$NODE1\nNODE2=$NODE2\nNSO_VERSION=$NSO_VERSION\n" > ./.env
printf "NODE1_IP=$NODE1_IP\nNODE2_IP=$NODE2_IP\nNSO_VIP=$NSO_VIP\n" >> ./.env
printf "MANAGER_IP=$MANAGER_IP\nSUBNET=$SUBNET\nGATEWAY=$GATEWAY\n" >> ./.env
printf "NCS_CLI_SSH=true\nNCS_WEBUI_TRANSPORT_SSL=true\nNCS_NETCONF_TRANSPORT_SSH=true\n" >> ./.env

if [ -f rule-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz ]
then
    echo "Using:"
    echo "rule-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz"
else
    echo >&2 "This demo require that the Tail-f HCC packages has been placed in the rule-etc folder. E.g.:"
    echo >&2 "rule-etc/ncs-$HCC_NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz"
    echo >&2 "Aborting..."
    exit 1
fi

printf "\n${GREEN}##### Reset the container setup\n${NC}"
docker compose --profile manager down -v
docker compose --profile nso down -v

docker compose build NODE-1 MANAGER

printf "\n${GREEN}##### Start the manager container\n${NC}"
docker compose --profile manager up --wait

printf "\n${GREEN}##### Start the NSO containers\n${NC}"
docker compose --profile nso up --wait

printf "\n${GREEN}##### Run a demo from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager /root/rule-etc/demo.sh

printf "\n${GREEN}##### Follow the NODE-1 NODE-2 MANAGER logs\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker compose logs --follow NODE-1 NODE-2 MANAGER
