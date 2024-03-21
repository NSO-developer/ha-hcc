#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

scrptname=${0##*/}
NODES=( ${NODE1} ${NODE2} ${NODE3} )

# certificate authority certs and keys
generate_self_signed_ca()
{
    ( set -xe
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
              -keyout "/ssl/private/ca.key" -nodes \
              -subj "/CN=self-signed CA" -sha384 -days 3652 \
              -out "/ssl/certs/ca.crt"
      chmod 600 "/ssl/private/ca.key" )
    if [ $? -ne 0 ]; then
        echo "$scrptname: error: failed to generate CA certs/keys" >&2
        exit 1
    fi
}

generate_host_certs()
{
    # umask removes group/other read/write access from private key
    ( set -x; umask 077 && \
          openssl req -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
                  -keyout "/$1/dist/ssl/private/$1.key" -nodes \
                  -out "/ssl/csr/$1.csr" -subj "/CN=$1" ) && \
        ( set -x; openssl x509 -req -CAcreateserial \
                          -in "/ssl/csr/$1.csr" \
                          -CA "/ssl/certs/ca.crt" \
                          -CAkey "/ssl/private/ca.key" \
                          -days 3652 -out "/$1/dist/ssl/certs/$1.crt" )

    if [ $? -ne 0 ]; then
        echo "$scrptname: error: failed to generate host certs/keys for $1" >&2
        exit 1
    fi
    cp  /ssl/certs/ca.crt /$1/dist/ssl/certs/ca.crt
    openssl x509 -noout -text -in /$1/dist/ssl/certs/$1.crt
}

generate_tls_certificates()
{
    mkdir -p /ssl/certs /ssl/crl /ssl/private /ssl/csr
    chmod 600 /ssl/private

    generate_self_signed_ca

    printf "${GREEN}##### Generate host certs/keys for ${NODE1} ${NODE2} ${NODE3}\n${NC}"
    for NODE in "${NODES[@]}" ; do
        mkdir -p /$NODE/dist/ssl/certs /$NODE/dist/ssl/private
        chmod 600 /$NODE/dist/ssl/private
        generate_host_certs "$NODE"
    done
    rm -rf /ssl
}
