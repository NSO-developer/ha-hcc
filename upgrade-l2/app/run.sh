#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODE_NAME=$(uname -n)
printf "${PURPLE}NODE_NAME: $NODE_NAME\n${NC}"
printf "${PURPLE}NODE1: ${NODE1_NAME} NODE1_IP: ${NODE1_IP}\n${NC}"
printf "${PURPLE}NODE2: ${NODE2_NAME} NODE2_IP: ${NODE2_IP}\n${NC}"
printf "${PURPLE}NSO_VIP: ${NSO_VIP}\n${NC}"

env | grep _ >> /home/admin/.pam_environment

printf "\n${PURPLE}##### Start the SSH daemon\n${NC}"
sudo /usr/sbin/sshd

printf "\n${PURPLE}##### Reset, setup, start NSO, and enable HA assuming start-up settings\n${NC}"
make stop &> /dev/null
make clean NSOVER=${NSO_VERSION} HCCVER=${HCC_VERSION} all
cp package-store/dummy-1.0.tar.gz ${NCS_RUN_DIR}/packages
cp package-store/ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz ${NCS_RUN_DIR}/packages
make start

ncs_cmd -u admin -g ncsadmin -o -c 'maction "/high-availability/enable"'

tail -F ${NCS_LOG_DIR}/devel.log
