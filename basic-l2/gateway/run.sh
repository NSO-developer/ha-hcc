#!/bin/bash

set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

NODE_NAME=$(uname -n)

printf "${PURPLE}NODE_NAME: $NODE_NAME\n${NC}"
printf "${PURPLE}NSO_VIP: ${NSO_VIP}\n${NC}"

socat TCP-LISTEN:12024,fork TCP:${NSO_VIP}:2024
