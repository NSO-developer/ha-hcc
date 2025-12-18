#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

function on_leader() { printf "${PURPLE}On leader CLI: ${NC}$@\n"; ssh -l admin -p 2024 -o LogLevel=ERROR ${NSO_VIP} "$@" ; }
function on_node() { printf "${PURPLE}On $1 CLI: ${NC}$2\n"; ssh -l admin -p 2024 -o LogLevel=ERROR "$1" "$2" ; }
function on_node_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -l admin -p 22 -o LogLevel=ERROR "$1" "$2" ; }
function as_root_sh() { printf "${PURPLE}On $1: ${NC}$2\n"; ssh -i /root/.ssh/upgrade-keys/id_ed25519 -l root -p 22 -o LogLevel=ERROR "$1" "$2" ; }
function scp_node() { printf "${PURPLE}scp from: $1 to: $2${NC}\n"; scp -o LogLevel=ERROR "$1" "$2" ; }

NODES=( ${NODE1} ${NODE2} ${NODE3} )

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

printf "\n${PURPLE}##### Copy the new NSO ${NEW_NSO_VERSION} version to all nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    scp_node "manager-etc/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin" "admin@$NODE:/tmp/"
done

LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"
printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"

printf "\n${PURPLE}##### The ARP entry for the ${NSO_VIP} VIP address\n${NC}"
arp -a

printf "\n${PURPLE}##### Enable read-only mode on the leader $CURRENT_LEADER\n${NC}"
on_leader "ha-raft read-only mode true"

printf "\n${PURPLE}##### Verify that all cluster nodes are in-sync\n${NC}"
while [ "$(on_leader 'show ha-raft status log replications state | include in-sync' | wc -l)" -lt "2" ] ; do
    printf "${RED}##### Waiting for all cluster nodes to become in-sync. Retry...\n${NC}"
    sleep .5
done

printf "\n${PURPLE}##### Backup before upgrading NSO\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_sh $NODE '${NCS_DIR}/bin/ncs-backup'
done

set +e
printf "\n${PURPLE}##### Compact the CDB write log, delete the raft state, and stop the nodes that will be followers after upgrade\n${NC}"
printf "\n${PURPLE}##### Note: need to compact before stopping NSO as the container will restart when NSO is stopped\n${NC}"
for NODE in "${NODES[@]}" ; do
    if [ "$NODE" != "${NODE1}" ] ; then
        on_node_sh $NODE 'touch $NCS_RUN_DIR/upgrade \
                          && touch $NCS_RUN_DIR/package_reload_force \
                          && rm $NCS_RUN_DIR/cdb/compact.lock \
                          && ncs --cdb-compact $NCS_RUN_DIR/cdb \
                          && rm -rf $NCS_RUN_DIR/state/raft \
                          && ${NCS_DIR}/bin/ncs --stop'
    fi
done

printf "\n${PURPLE}##### Compact the CDB write log, delete the raft state, and stop the new leader ${NODE1} after the upgrade\n${NC}"
on_node_sh ${NODE1} 'touch $NCS_RUN_DIR/upgrade \
                     && touch $NCS_RUN_DIR/package_reload \
                     && rm $NCS_RUN_DIR/cdb/compact.lock \
                     && ncs --cdb-compact $NCS_RUN_DIR/cdb \
                     && rm -rf $NCS_RUN_DIR/state/raft \
                     && ${NCS_DIR}/bin/ncs --stop'

# Since the NSO containers restart when NSO is stopped and we are pretending they are devices
printf "\n${PURPLE}##### Verify that all nodes are waiting for the upgrade\n${NC}"
for NODE in "${NODES[@]}" ; do
    until on_node_sh $NODE '[ -f $NCS_RUN_DIR/initialized ]' ; do
        printf "${RED}##### Waiting for $NODE to come back up. Retry...\n${NC}"
        sleep .5
    done
done
set -e

# Not actually needed here since we are replacing existing packages with recompiled ones, and paris2.fra and paris3.fra does not have any packages in their NCS_RUN_DIR/packages folder (only paris1.fra).
# But if we had done a package upgrade using packages ha sync and-reload before stopping NSO, then we need to clean up.
# Or if we to start the the cluster back up from another node than paris1.fra.
printf "\n${PURPLE}##### Delete the old packages on the nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node_sh $NODE "rm -f $NCS_RUN_DIR/packages/*"
done

# Can use the container shared volumes here, but if no containers and shared volumes, for example, use scp
printf "\n${PURPLE}##### Upgrade the HCC package for the new leader ${NODE1}\n${NC}"
cp /root/manager-etc/ncs-${NEW_HCC_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz /root/package-store
scp_node "/root/package-store/ncs-${NEW_HCC_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz" "admin@${NODE1}:/home/admin/etc/package-store/tailf-hcc.tar.gz"

printf "\n${PURPLE}##### Rebuild and upgrade the dummy-1.0 package for the leader ${NODE1}\n${NC}"
tar xvfz /root/package-store/dummy-1.0.tar.gz
make -C dummy-1.0/src/ clean all
tar cvfz /root/package-store/dummy-1.0.tar.gz dummy-1.0
rm -rf dummy-1.0
scp_node "/root/package-store/dummy-1.0.tar.gz" "admin@${NODE1}:/home/admin/etc/package-store/dummy-1.0.tar.gz"

printf "\n${PURPLE}##### Rebuild and upgrade the token-1.0 package for the leader ${NODE1}\n${NC}"
tar xvfz /root/package-store/token-1.0.tar.gz
make -C token-1.0/src/ clean all
tar cvfz /root/package-store/token-1.0.tar.gz token-1.0
rm -rf token-1.0
scp_node "/root/package-store/token-1.0.tar.gz" "admin@${NODE1}:/home/admin/etc/package-store/token-1.0.tar.gz"

printf "\n${PURPLE}##### Install NSO ${NEW_NSO_VERSION} on all nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    as_root_sh $NODE "chmod u+x /tmp/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin"
    set +e
    as_root_sh $NODE "[ -d $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION ] && rm -rf $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION"
    set -e
    as_root_sh "$NODE" "/tmp/nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin \
        --system-install --run-as-user admin --non-interactive && \
        LEGACY_PRIV_1=\"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/core/confd/priv/cmdwrapper\"; \
        LEGACY_PRIV_2=\"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/netsim/confd/lib/confd/lib/core/confd/priv/cmdwrapper\"; \
        if [ -e \"\$LEGACY_PRIV_1\" ]; then \
            CHOWN_PATH=\"\$LEGACY_PRIV_1\"; \
            CHMOD_PATH=\"\$LEGACY_PRIV_2\"; \
        else \
            CONFD_DIR=\$(ls -d \"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION\"/lib/ncs/lib/confd-* | head -n1); \
            CONFD_VERSION=\"\${CONFD_DIR##*-}\"; \
            CHOWN_PATH=\"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/lib/ncs/lib/confd-\$CONFD_VERSION/priv/cmdwrapper\"; \
            CHMOD_PATH=\"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION/netsim/confd/lib/confd/lib/confd-\$CONFD_VERSION/priv/cmdwrapper\"; \
        fi; \
        chown root \"\$CHOWN_PATH\"; \
        chmod u+s \"\$CHMOD_PATH\"; \
        rm \"$NCS_ROOT_DIR/current\"; \
        ln -s \"$NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION\" \"$NCS_ROOT_DIR/current\""
done

# Since the NSO containers restarted when NSO was stopped and we are pretending they are devices
for NODE in "${NODES[@]}" ; do
    printf "\n${PURPLE}##### Start NSO on $NODE\n${NC}"
    on_node_sh $NODE "rm -f  $NCS_RUN_DIR/upgrade"
done

set +e
for NODE in "${NODES[@]}" ; do
    until on_node $NODE "show ncs-state version" = "ncs-state version $NEW_NSO_VERSION" ; do
        printf "${RED}##### Waiting for NSO on $NODE to come back up. Retry...\n${NC}"
        sleep 1
    done
done

printf "\n${PURPLE}##### Re-initialize the HA cluster using the create-cluster action from ${NODE1}\n${NC}"
on_node ${NODE1} "ha-raft create-cluster member [ ${NODE2} ${NODE3} ]"

until ping -c1 -w2 ${NSO_VIP} >/dev/null 2>&1 ; do
    printf "${RED}##### Waiting for the ${NSO_VIP} VIP route to the new leader. Retry...\n${NC}"
    sleep 1
done
set -e

LOCAL_NODE=$(on_leader "show ha-raft status local-node")
tmp="${LOCAL_NODE##* }"
CURRENT_LEADER="${tmp::-1}"

printf "\n${GREEN}##### Current leader node: ${PURPLE}$CURRENT_LEADER\n${NC}"
printf "\n${PURPLE}##### Show ha-raft role status on all nodes\n${NC}"
for NODE in "${NODES[@]}" ; do
    on_node $NODE "show ha-raft status role"
done

printf "\n${GREEN}##### Done!\n${NC}"