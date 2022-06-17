#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
token=$(openssl rand -base64 32)
if [ $(${NCS_DIR}/bin/ncs_cmd -u admin -o -c "cdb_exists \"/tokens/token{$1}\"") = "no" ]
then
    ${NCS_DIR}/bin/ncs_cmd -u admin -o -c "cdb_create \"/tokens/token{$1}\"; cdb_set \"/tokens/token{$1}/token\" \"$token\""
else
    ${NCS_DIR}/bin/ncs_cmd -u admin -o -c "cdb_set \"/tokens/token{$1}/token\" \"$token\""
fi
printf "token $token"
