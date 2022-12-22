#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODE_NAME=$(uname -n)

function version_ge() { test "$(printf '%s\n' "$@" | sort -rV | head -n 1)" == "$1"; }
NSO60=6.0

# NSO 6 use primary secondary instead of master slave
if version_ge ${NSO_VERSION} $NSO60; then
  PRIMARY="primary"
  SECONDARY="secondary"
else
  PRIMARY="master"
  SECONDARY="slave"
fi

printf "${PURPLE}NODE_NAME: $NODE_NAME\n${NC}"
printf "${PURPLE}NODE1: ${NODE1_NAME} NODE1_IP: ${NODE1_IP}\n${NC}"
printf "${PURPLE}NODE2: ${NODE2_NAME} NODE2_IP: ${NODE2_IP}\n${NC}"
printf "${PURPLE}NSO_VIP: ${NSO_VIP}\n${NC}"

printf "\n${PURPLE}##### Apply a temporary privilege issue fix to the Tail-f HCC package\n${NC}"
make HCC_TARBALL_NAME="ncs-${NSO_VERSION}-tailf-hcc-${TAILF_HCC_VERSION}.tar.gz" hcc-fix

printf "\n${PURPLE}##### Reset, setup, start, and enable HA assuming start-up settings\n${NC}"
make stop &> /dev/null
make clean NODE1_IP=${NODE1_IP} NODE2_IP=${NODE2_IP} PRIMARY=$PRIMARY SECONDARY=$SECONDARY all start
ncs_cmd -u admin -g ncsadmin -o -c 'maction "/high-availability/enable"'

if [ "${NODE_NAME}" = ${NODE1_NAME} ] ; then
    while [[ $(ncs_cmd -u admin -g ncsadmin -a ${NODE1_IP} -c "mrtrans; maapi_num_instances /high-availability/status/connected-$SECONDARY") != "1" ]] ; do
        printf '.'
        sleep 1
    done

    printf "\n\n${PURPLE}##### Initial high-availability config for both nodes\n${NC}"
    NCS_IPC_ADDR=${NODE1_IP} ncs_load -u admin -g ncsadmin -W -Fp -p /high-availability

    CURRENT_VIP=$(ncs_cmd -u admin -g ncsadmin -a ${NSO_VIP} -o -c "mrtrans; mget /high-availability/status/current-id")
    printf "\n\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

    printf "\n${PURPLE}##### Add some dummy config to node 1, replicated to secondary node 2\n${NC}"
    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE1_IP} << EOF
config
dummies dummy d1 dummy 1.2.3.4
commit
end
show high-availability | notab | nomore
show running-config dummies | nomore
EOF

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE2_IP} << EOF
show high-availability status | notab | nomore
show running-config dummies | nomore
EOF

    printf "\n\n${PURPLE}##### Stop node 1 to make node 2 failover to primary role\n${NC}"
    make stop

    printf "\n"
    RI=$(ncs_cmd -u admin -g ncsadmin -a ${NODE2_IP} -c 'mrtrans; maapi_get "/high-availability/settings/reconnect-interval"')
    RA=$(ncs_cmd -u admin -g ncsadmin -a ${NODE2_IP} -c 'mrtrans; maapi_get "/high-availability/settings/reconnect-attempts"')
    ID=$((RI*RA))
    while [[ $(ncs_cmd -u admin -g ncsadmin -a ${NODE2_IP} -o -c 'mrtrans; maapi_get "/high-availability/status/mode"') != "$PRIMARY" ]]; do
        printf "${RED}#### Waiting for node 2 to fail reconnect to node 1 and assume primary role... $ID\n${NC}"
        if [[ $ID > 0 ]]; then
            let ID--
        fi
        sleep 1
    done

    set +e
    until ping -c1 -w3 ${NSO_VIP} >/dev/null 2>&1
    do
      printf "${RED}#### Failed to ping the ${NSO_VIP} VIP. Retry...\n${NC}"
    done
    set -e

    CURRENT_VIP=$(ncs_cmd -u admin -g ncsadmin -a ${NSO_VIP} -o -c "mrtrans; maapi_get /high-availability/status/current-id")
    printf "\n\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE2_IP} << EOF
show high-availability status | notab | nomore
show alarms alarm-list | notab | nomore
EOF

    printf "\n\n${PURPLE}##### Start node 1 that will now assume secondary role\n${NC}"
    make start

    printf "\n\n"
    while [[ $(ncs_cmd -u admin -g ncsadmin -a ${NODE1_IP} -o -c 'mrtrans; maapi_get "/high-availability/status/mode"') != "$SECONDARY" ]]; do
        printf "${RED}#### Waiting for node 1 to become secondary to node 2...\n${NC}"
        sleep 1
    done

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE1_IP} << EOF
show high-availability status | notab | nomore
EOF

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE2_IP} << EOF
show high-availability status | notab | nomore
EOF

    printf "\n\n${PURPLE}##### Role-revert the nodes back to start-up settings${NC}"

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE1_IP} << EOF
high-availability disable
EOF

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE2_IP} << EOF
high-availability disable
EOF

    NCS_IPC_ADDR=${NODE1_IP} ncs_cli -n -u admin -g ncsadmin -C << EOF
high-availability enable
EOF

    printf "\n\n"
    while [[ $(ncs_cmd -u admin -g ncsadmin -a ${NODE1_IP} -o -c 'mrtrans; maapi_get "/high-availability/status/mode"') != "$PRIMARY" ]]; do
        printf "${RED}#### Waiting for node 1 to revert to primary role...\n${NC}"
        sleep 1
    done

    NCS_IPC_ADDR=${NODE2_IP} ncs_cli -n -u admin -g ncsadmin -C << EOF
high-availability enable
EOF

    printf "\n\n"
    while [[ $(ncs_cmd -u admin -g ncsadmin -a ${NODE2_IP} -o -c 'mrtrans; maapi_get "/high-availability/status/mode"') != "$SECONDARY" ]]; do
        printf "${RED}#### Waiting for node 2 to revert to secondary role for primary node 1...\n${NC}"
        sleep 1
    done

    CURRENT_VIP=$(ncs_cmd -u admin -g ncsadmin -a ${NSO_VIP} -o -c "mrtrans; mget /high-availability/status/current-id")
    printf "\n\n${GREEN}##### Current VIP node: ${PURPLE}$CURRENT_VIP\n${NC}"

    ncs_cli -n -u admin -g ncsadmin -C -A ${NODE1_IP} << EOF
show high-availability status | notab | nomore
show running-config dummies | nomore
EOF

    ncs_cli -n -u admin -g ncsadmin -n -u admin -g ncsadmin -C -A ${NODE2_IP} << EOF
show high-availability status | notab | nomore
show running-config dummies | nomore
EOF

    printf "\n\n${GREEN}##### Done!\n${NC}"
fi

tail -F ${NCS_LOG_DIR}/devel.log
