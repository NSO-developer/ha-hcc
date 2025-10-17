#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODES=( ${NODE1} ${NODE2} )

function on_primary() { printf "${PURPLE}On primary CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_primary_sh() { printf "${PURPLE}On primary: ${NC}$@\n"; ssh -l nso -p 22 -o ServerAliveInterval=1 -o ServerAliveCountMax=1 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o LogLevel=ERROR "$1" "$2"; }

ARRAY=$(hostname -i)
MANAGER_IP="${ARRAY%% *}"
while [ ${#MANAGER_IP} = 0 ] ; do
  ARRAY=$(hostname -i)
  MANAGER_IP="${ARRAY%% *}"
  printf "\n${RED}##### Waiting for the DNS to be updated with the container IP address\n${NC}"
  sleep .5
done
printf "\n${PURPLE}##### Manager IP $MANAGER_IP\n${NC}"

printf "\n${PURPLE}##### Change the FRR config and add bgpd\n${NC}"

sed -i.bak -e "s/bgpd=no/bgpd=yes/g" /etc/frr/daemons

nft add table nat
nft 'add chain nat postrouting { type nat hook postrouting priority 100 ; }'
nft 'add chain nat prerouting { type nat hook prerouting priority -100; }'
nft add rule nat prerouting tcp dport 12024 dnat ${NSO_VIP}:2024
nft add rule nat postrouting masquerade

printf "
hostname router
router bgp ${MANAGER_AS}
 bgp router-id $MANAGER_IP
 no bgp ebgp-requires-policy
 neighbor ${NODE2_IP} remote-as ${NODE2_AS}
 neighbor ${NODE1_IP} remote-as ${NODE1_AS}
!
line vty
!
" >> /etc/frr/frr.conf

printf "
" >> /etc/frr/vtysh.conf

printf "\n${PURPLE}##### Start FRR\n${NC}"
/usr/lib/frr/frrinit.sh start
printf "\n${GREEN}##### Started!\n${NC}"

vtysh << EOF
show running-config
show bgp summary
show bgp neighbor
show ip bgp
EOF

printf "\n${PURPLE}##### Configure tailf-hcc the HA cluster\n${NC}"
for NODE in "${NODES[@]}" ; do 
    on_node $NODE "config; hcc enabled vip-address ${NSO_VIP} bgp node ${NODE1} enabled as ${NODE1_AS} router-id ${NODE1_IP} neighbor ${NODE1_GW} as ${MANAGER_AS} ttl-min 254;
hcc bgp node ${NODE2} enabled as ${NODE2_AS} router-id ${NODE2_IP} neighbor ${NODE2_GW} as ${MANAGER_AS} ttl-min 254;
high-availability token very-secret;
high-availability settings enable-failover true;
high-availability ha-node ${NODE1} address ${NODE1_IP} nominal-role primary;
high-availability ha-node ${NODE2} address ${NODE2_IP} nominal-role secondary failover-primary true;
high-availability settings start-up assume-nominal-role true;
high-availability settings start-up join-ha true;
high-availability settings reconnect-interval 1;
high-availability settings reconnect-attempts 3;
commit"
done

printf "\n${PURPLE}##### Run the high availability enable action\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node $NODE "high-availability enable"
done

while [[ "$(on_node $NODE1 'show high-availability status connected-secondary')" != *"$NODE2"* ]] ; do
  printf "${RED}#### Waiting for secondary $NODE2 to connect with primary $NODE1...\n${NC}"
  sleep 1
done

set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to initialize. Retry...\n${NC}"
    sleep 1
done
set -e

CURRENT_ID=$(on_primary "show high-availability status current-id")
tmp="${CURRENT_ID##* }"
PRIMARY="${tmp::-1}"

printf "\n${GREEN}##### Current primary node: ${PURPLE}$PRIMARY\n${NC}"

printf "\n${PURPLE}Show the route status on the manager and primary ($PRIMARY) nodes\n${NC}"
ip route
vtysh << EOF
show bgp summary
show ip bgp
EOF

on_primary "show hcc"
on_primary_sh "gobgp global rib; gobgp neighbor"

printf "\n${GREEN}##### A two node HA demo\n${NC}"

printf "\n${PURPLE}##### Add some dummy config to primary node $PRIMARY, replicated to secondary $NODE2\n${NC}"
on_primary "config;
dummies dummy d1 dummy 1.2.3.4;
commit"

printf "\n${PURPLE}##### Check the dummy config on the secondary node\n${NC}"
on_node $NODE2 "show running-config dummies"

printf "\n${PURPLE}##### Get the reconnect settings\n${NC}"
INTERVAL=$(on_primary "show running-config high-availability settings reconnect-interval")
tmp="${INTERVAL##* }"
RI="${tmp::-1}"
ATTEMPTS=$(on_primary "show running-config high-availability settings reconnect-attempts")
tmp="${ATTEMPTS##* }"
RA="${tmp::-1}"
TIMEOUT=$((RA*RI))

printf "\n${PURPLE}##### Observe a failover by bringing down $PRIMARY (current primary)\n${NC}"
set +e
on_primary_sh "/opt/ncs/current/bin/ncs --stop"

printf "${PURPLE}##### The secondary will attempt to reconnect to the primary $RA times every $RI s (timeout after $TIMEOUT s)\n${NC}"
printf "${PURPLE}##### Test the ${NSO_VIP} VIP route to the new primary\n${NC}"
counter=0
until [ $counter -gt 1 ] ; do
    if ping -c 1 ${NSO_VIP} &> /dev/null ; then
        ((counter++))
    fi
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to the new primary. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n${PURPLE}##### Get the new primary name\n${NC}"
SECONDARY=$PRIMARY
CURRENT_ID=$(on_primary "show high-availability status current-id")
tmp="${CURRENT_ID##* }"
PRIMARY="${tmp::-1}"

printf "\n${GREEN}##### Current primary node: ${PURPLE}$PRIMARY\n${NC}"

printf "\n${PURPLE}##### Try add additional config on the primary $PRIMARY while in read-only mode waiting for the secondary $SECONDARY\n${NC}"
on_primary "config;
dummies dummy d2-new dummy 2.1.3.4;
commit"

printf "\n${PURPLE}##### Wait for $SECONDARY to come back and follow the new primary $PRIMARY\n${NC}"
set +e
while [[ "$(on_node $SECONDARY 'show high-availability status primary-id')" != *"$PRIMARY"* ]] ; do
  printf "${RED}#### Waiting for $SECONDARY to follow $PRIMARY...\n${NC}"
  sleep 1
done
set -e

printf "\n${PURPLE}##### Retry adding the config on the primary $PRIMARY\n${NC}"
on_primary "config;
dummies dummy d2-new dummy 2.1.3.4;
commit"

printf "\n${PURPLE}##### Observe that the new configuraion is replicated as well\n${NC}"
on_node $SECONDARY "show running-config dummies"

printf "\n${PURPLE}The updated ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${PURPLE}##### Role-revert the nodes back to start-up settings\n${NC}"
on_node $SECONDARY "high-availability be-primary"
on_node $PRIMARY "high-availability be-secondary-to node $SECONDARY"

set +e
while [[ "$(on_node $NODE1 'high-availability status mode')" != *"primary"* ]] ; do
  printf "${RED}#### Waiting for $NODE1 to revert to primary role...\n${NC}"
  sleep 1
done

while [[ "$(on_node $NODE1 'high-availability status mode')" != *"secondary"* ]] ; do
  printf "${RED}#### Waiting for $NODE2 to revert to secondary role...\n${NC}"
  sleep 1
done

printf "\n${PURPLE}##### Test the ${NSO_VIP} VIP route to the new primary\n${NC}"
counter=0
until [ $counter -gt 1 ] ; do
    if ping -c 1 ${NSO_VIP} &> /dev/null ; then
        ((counter++))
    fi
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to the new primary. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n${PURPLE}##### Get the new primary name\n${NC}"
SECONDARY=$PRIMARY
CURRENT_ID=$(on_primary "show high-availability status current-id")
tmp="${CURRENT_ID##* }"
PRIMARY="${tmp::-1}"

printf "\n${GREEN}##### Current primary node: ${PURPLE}$PRIMARY\n\n${NC}"

on_primary "show high-availability status"
on_node $SECONDARY "show high-availability status"

printf "\n${PURPLE}Show the route status on the manager and primary ($PRIMARY) nodes\n${NC}"
ip route
vtysh << EOF
show bgp summary
show ip bgp
EOF

on_primary "show hcc"
on_primary_sh "gobgp global rib; gobgp neighbor"

printf "\n${GREEN}##### Done!\n${NC}"