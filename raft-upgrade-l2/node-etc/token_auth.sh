#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set
read -r token_str
token=$(echo "$token_str" | grep -o -P '(?<=\[).*(?=;)')
user=$(${NCS_DIR}/bin/ncs_cmd -c "mrtrans; xpath_eval_expr /tokens/token[token='$token']/name" )
if [ "$user" != "" ]
then
    printf "accept $(id -G -n $user) $(id -u $user) $(id -G $user) $(eval echo "~$user") $user\n"
else
    printf "reject\n"
fi
