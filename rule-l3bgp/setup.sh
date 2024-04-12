#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NSO_VERSION="6.2.4"
HCC_NSO_VERSION="6.2.4"
HCC_VERSION="6.0.2"

NODE1=paris.fra
NODE2=london.eng
NODE1_IP="192.168.32.99"
NODE1_GW="192.168.32.2"
NODE1_AS="64511"
NODE2_IP="192.168.31.98"
NODE2_GW="192.168.31.2"
NODE2_AS="64512"
MANAGER_AS="64514"
NSO_VIP="192.168.23.122"
SUBNET1="192.168.32.0/24"
SUBNET2="192.168.31.0/24"
NET1="net1"
NET2="net2"

printf "NSO_VERSION=$NSO_VERSION\nNSO_VIP=$NSO_VIP\nMANAGER_AS=$MANAGER_AS\nNET1=$NET1\nNET2=$NET2\n" > ./.env
printf "NODE1=$NODE1\nNODE1_IP=$NODE1_IP\nNODE1_GW=$NODE1_GW\nNODE1_AS=$NODE1_AS\nSUBNET1=$SUBNET1\n" >> ./.env
printf "NODE2=$NODE2\nNODE2_IP=$NODE2_IP\nNODE2_GW=$NODE2_GW\nNODE2_AS=$NODE2_AS\nSUBNET2=$SUBNET2\n" >> ./.env

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

printf "${GREEN}##### Connect node networks with the manager\n${NC}"
docker network connect --ip $NODE1_GW $NET1 manager
docker network connect --ip $NODE2_GW $NET2 manager

printf "\n${GREEN}##### Run a demo from the manager node\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker exec manager /root/rule-etc/demo.sh

printf "\n${GREEN}##### Follow the NODE-1 NODE-2 MANAGER logs\n${NC}"
printf "${RED}##### Press any key to continue or ctrl-c to exit\n${NC}"
read -n 1 -s -r
docker compose logs --follow NODE-1 NODE-2 MANAGER
