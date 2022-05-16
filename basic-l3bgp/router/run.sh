#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODE_NAME=$(uname -n)
NODE3_IP=$(dig +short $NODE_NAME)
while [ ${#NODE3_IP} = 0 ] ; do
  NODE3_IP=$(dig +short $NODE_NAME)
  printf "\n\n${RED}##### Waiting for the DNS to be updated with the container IP address\n${NC}"
  sleep .5
done

printf "${PURPLE}NODE_NAME: $NODE_NAME\n${NC}"
printf "${PURPLE}NODE1_IP: $NODE1_IP NODE1_AS: $NODE1_AS\n${NC}"
printf "${PURPLE}NODE2_IP: $NODE2_IP NODE2_AS: $NODE2_AS\n${NC}"
printf "${PURPLE}NODE3_IP: $NODE3_IP NODE3_AS: $NODE3_AS\n${NC}"
printf "${PURPLE}SUBNET1: $SUBNET1 SUBNET2: $SUBNET2\n${NC}"
printf "${PURPLE}NSO_VIP: ${NSO_VIP}\n${NC}"
printf "\n\n${PURPLE}##### Change the FRR config and add bgpd\n${NC}"

sed -i.bak -e "s/bgpd=no/bgpd=yes/g" /etc/frr/daemons

nft add table nat
nft 'add chain nat postrouting { type nat hook postrouting priority 100 ; }'
nft 'add chain nat prerouting { type nat hook prerouting priority -100; }'
nft add rule nat prerouting tcp dport 12024 dnat ${NSO_VIP}:2024
nft add rule nat postrouting masquerade

printf "
hostname router
router bgp ${NODE3_AS}
 bgp router-id $NODE3_IP
 no bgp ebgp-requires-policy
 neighbor ${NODE2_IP} remote-as ${NODE2_AS}
 neighbor ${NODE1_IP} remote-as ${NODE1_AS}
!
line vty
!
" >> /etc/frr/frr.conf

printf "
" >> /etc/frr/vtysh.conf

printf "\n\n${PURPLE}##### Start FRR\n${NC}"

/usr/lib/frr/frrinit.sh start

printf "\n\n${GREEN}##### Started!\n${NC}"

vtysh << EOF
show running-config
show bgp summary
show bgp neighbor
show ip bgp
EOF

tail -F -n0 run.sh
