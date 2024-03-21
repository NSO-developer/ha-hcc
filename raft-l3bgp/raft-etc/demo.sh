#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODES=( ${NODE1} ${NODE2} ${NODE3} )

function on_leader() { printf "${PURPLE}On leader CLI: ${NC}$@\n"; ssh -l admin -p 2024 -q -o StrictHostKeyChecking=no -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_leader_sh() { printf "${PURPLE}On leader: ${NC}$@\n"; ssh -l admin -p 22 -q -o StrictHostKeyChecking=no -o ServerAliveInterval=1 -o ServerAliveCountMax=1 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -q -o StrictHostKeyChecking=no -o LogLevel=ERROR "$1" "$2" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -p 22 -q -o StrictHostKeyChecking=no -o LogLevel=ERROR "$1" "$2" ; }

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
 neighbor ${NODE3_IP} remote-as ${NODE3_AS}
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

printf "\n${PURPLE}##### Initialize the HA cluster using the create-cluster action\n${NC}"
on_node ${NODE1} "ha-raft create-cluster member [ ${NODE2} ${NODE3} ]"

while [[ "$(on_node ${NODE1} 'show ha-raft status role')" != *"leader"* ]] ; do
    printf "${RED}##### Waiting for the leader ${NODE1} to initialize. Retry...\n${NC}"
    sleep 1
done

printf "\n${PURPLE}##### Initialize HCC\n${NC}"
on_node $NODE1 "config;
hcc enabled vip-address ${NSO_VIP} bgp node ${NODE1} enabled gobgp-bin-dir /usr/bin as ${NODE1_AS} router-id ${NODE1_IP} neighbor ${NODE1_GW} as ${MANAGER_AS} ttl-min 254;
hcc bgp node ${NODE2} enabled gobgp-bin-dir /usr/bin as ${NODE2_AS} router-id ${NODE2_IP} neighbor ${NODE2_GW} as ${MANAGER_AS} ttl-min 254;
hcc bgp node ${NODE3} enabled gobgp-bin-dir /usr/bin as ${NODE3_AS} router-id ${NODE3_IP} neighbor ${NODE3_GW} as ${MANAGER_AS} ttl-min 254;
commit"

printf "\n${GREEN}##### A three node HA setup demo\n${NC}"
set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to initialize. Retry...\n${NC}"
    sleep 1
done
set -e

LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"

printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "\n${PURPLE}##### Add some dummy config to $CURRENT_LEADER, replicated to other nodes\n${NC}"
on_leader "config; dummies dummy d1 dummy 1.2.3.4; commit; end; show running-config dummies | nomore"

printf "\n${PURPLE}##### Check the dummy config on follower nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    if [ "$NODE" != "$CURRENT_LEADER" ] ; then
        on_node $NODE "show running-config dummies"
    fi
done

printf "\n${PURPLE}##### Observe a failover by bringing down $CURRENT_LEADER (current leader)\n${NC}"
set +e
on_leader_sh "ncs --stop"

until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to the new leader. Retry...\n${NC}"
    sleep 1
done
set -e

PREV_LEADER=$CURRENT_LEADER
LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"

printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "${PURPLE}##### Add additional config on the leader $CURRENT_LEADER\n${NC}"
on_leader "config; dummies dummy d2-new dummy 2.1.3.4; commit; end; show running-config dummies | nomore"

printf "\n${PURPLE}Show that the new config is replicated to all remaining nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    if [ "$NODE" != "$PREV_LEADER" ] ; then
        on_node $NODE "show running-config dummies"
    fi
done

printf "\n${PURPLE}Wait for $PREV_LEADER to come back and follow the new leader $CURRENT_LEADER\n${NC}"
set +e
while [[ "$(on_node $PREV_LEADER 'show ha-raft status leader')" != *"$CURRENT_LEADER"* ]] ; do
  printf "${RED}#### Waiting for $PREV_LEADER to follow $CURRENT_LEADER...\n${NC}"
  sleep 1
done
set -e

printf "\n${PURPLE}Observe that the new data is replicated as well\n${NC}"
on_node $PREV_LEADER "show running-config dummies"

printf "\n${PURPLE}Show the route status on the manager and leader ($CURRENT_LEADER) nodes\n${NC}"

ip route
vtysh << EOF
show bgp summary
show ip bgp
EOF

on_leader "show hcc"
on_leader_sh "gobgp global rib; gobgp neighbor"

printf "\n${GREEN}##### Done!\n${NC}"
