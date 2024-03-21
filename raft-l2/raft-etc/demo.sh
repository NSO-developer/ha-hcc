#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODES=( ${NODE1} ${NODE2} ${NODE3} )

function on_leader() { printf "${PURPLE}On leader CLI: ${NC}$@\n"; ssh -l admin -p 2024 -q -o StrictHostKeyChecking=no -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_leader_sh() { printf "${PURPLE}On leader: ${NC}$@\n"; ssh -l admin -p 22 -q -o ServerAliveInterval=1 -o ServerAliveCountMax=1 -o StrictHostKeyChecking=no -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -q -o StrictHostKeyChecking=no -o LogLevel=ERROR "$1" "$2" ; }

printf "\n${PURPLE}##### Initialize tailf-hcc\n${NC}"
on_node ${NODE1} "config; hcc enabled vip-address ${NSO_VIP}; commit"

printf "\n${PURPLE}##### Initialize the HA cluster using the create-cluster action\n${NC}"
on_node ${NODE1} "ha-raft create-cluster member [ ${NODE2} ${NODE3} ]"

set +e
until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to initialize. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n${PURPLE}The updated ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"

printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "\n${GREEN}##### A three node HA demo\n${NC}"

printf "\n${PURPLE}##### Add some dummy config to $CURRENT_LEADER, replicated to other nodes\n${NC}"
on_leader "config;
dummies dummy d1 dummy 1.2.3.4;
commit;
end;
show running-config dummies | nomore"

printf "\n${PURPLE}##### Check the dummy config on follower nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    if [ "$NODE" != "$CURRENT_LEADER" ] ; then
        on_node $NODE "show running-config dummies"
    fi
done

printf "\n${PURPLE}##### Observe a failover by bringing down $CURRENT_LEADER (current leader)\n${NC}"
set +e
on_leader_sh "ncs --stop"

printf "${PURPLE}##### Test the ${NSO_VIP} VIP route to the new leader\n${NC}"
counter=0
until [ $counter -gt 1 ] ; do
    if ping -c 1 ${NSO_VIP} &> /dev/null ; then
        ((counter++))
    fi
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to the new leader. Retry...\n${NC}"
    sleep 1
done
set -e

printf "\n${PURPLE}##### Get the new leader name\n${NC}"
PREV_LEADER=$CURRENT_LEADER
LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"

printf "${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "\n${PURPLE}##### Add additional config on the leader $CURRENT_LEADER\n${NC}"
on_leader "config;
dummies dummy d2-new dummy 2.1.3.4;
commit;
end;
show running-config dummies | nomore"

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

printf "\n${PURPLE}Observe that the configuration data is replicated as well\n${NC}"
on_node $PREV_LEADER "show running-config dummies"

printf "\n${PURPLE}The updated ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${GREEN}##### Done!\n${NC}"
