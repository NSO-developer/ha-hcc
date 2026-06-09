#!/bin/sh
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

scrptname=${0##*/}
NODES=( ${NODE1} ${NODE2} ${NODE3} )

subject_alt_name_entry()
{
    case "$1" in
        ""|*_* )
            return
            ;;
        *:* )
            printf "IP:%s" "$1"
            ;;
        *[!0-9.]* )
            printf "DNS:%s" "$1"
            ;;
        *.* )
            printf "IP:%s" "$1"
            ;;
        * )
            printf "DNS:%s" "$1"
            ;;
    esac
}

create_subject_alt_name()
{
    CERT_NAME="$1"
    shift

    SAN=""
    for HOST in "$CERT_NAME" "$@" ; do
        ENTRY=$(subject_alt_name_entry "$HOST")
        if [ -n "$ENTRY" ]; then
            if [ -n "$SAN" ]; then
                SAN="${SAN}, ${ENTRY}"
            else
                SAN="$ENTRY"
            fi
        fi
    done

    if [ -n "$SAN" ]; then
        printf "subjectAltName=%s\n" "$SAN" > "/ssl/csr/$CERT_NAME.san"
    fi
}

node_ip()
{
    case "$1" in
        "$NODE1") printf "%s" "${NODE1_IP:-}" ;;
        "$NODE2") printf "%s" "${NODE2_IP:-}" ;;
        "$NODE3") printf "%s" "${NODE3_IP:-}" ;;
    esac
}

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
    NODE_IP=$(node_ip "$1")
    create_subject_alt_name "$1" "$NODE_IP"

    # umask removes group/other read/write access from private key
    ( set -x; umask 077 && \
          openssl req -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 \
                  -keyout "/$1/etc/dist/ssl/private/$1.key" -nodes \
                  -out "/ssl/csr/$1.csr" -subj "/CN=$1" ) && \
        ( set -x; openssl x509 -req -CAcreateserial \
                          -in "/ssl/csr/$1.csr" \
                          -CA "/ssl/certs/ca.crt" \
                          -CAkey "/ssl/private/ca.key" \
                          -extfile "/ssl/csr/$1.san" \
                          -days 3652 -out "/$1/etc/dist/ssl/certs/$1.crt" )

    if [ $? -ne 0 ]; then
        echo "$scrptname: error: failed to generate host certs/keys for $1" >&2
        exit 1
    fi
    cp  /ssl/certs/ca.crt /$1/etc/dist/ssl/certs/ca.crt
    openssl x509 -noout -text -in /$1/etc/dist/ssl/certs/$1.crt
}

generate_tls_certificates()
{
    mkdir -p /ssl/certs /ssl/crl /ssl/private /ssl/csr
    chmod 700 /ssl/private

    generate_self_signed_ca

    printf "${GREEN}##### Generate host certs/keys for ${NODE1} ${NODE2} ${NODE3}\n${NC}"
    for NODE in "${NODES[@]}" ; do
        mkdir -p /$NODE/etc/dist/ssl/certs \
                 /$NODE/etc/dist/ssl/private \
                 /$NODE/etc/dist/ssl/crls
        chmod 755 /$NODE/etc/dist/ssl \
                  /$NODE/etc/dist/ssl/certs \
                  /$NODE/etc/dist/ssl/crls
        chmod 700 /$NODE/etc/dist/ssl/private
        generate_host_certs "$NODE"
    done
}
