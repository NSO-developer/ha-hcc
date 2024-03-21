#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

printf "${GREEN}##### Reset the container setup\n${NC}"
docker compose --profile manager down -v
docker compose --profile nso down -v
rm .env
