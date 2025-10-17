FROM debian:12-slim

ARG NSO_VERSION
ARG NSO_ARCH

ENV DEBIAN_FRONTEND=noninteractive

COPY manager-etc/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin /tmp/
RUN apt-get update \
    && apt-get install -y --no-install-recommends net-tools openssh-client \
    iputils-ping iproute2 libexpat1 make python3 python3-requests \
    python3-paramiko rsyslog openssl curl \
    && chmod u+x /tmp/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin \
    && /tmp/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin /nso-${NSO_VERSION} \
    && sed -i.bak -e 's/#module(load="imtcp")/module(load="imtcp")/' \
                  -e 's|#input(type="imtcp" port="514")|input(type="imtcp" port="514")|' \
                  -e '/imklog/s/^/#/' \
                  /etc/rsyslog.conf \
    && echo 'daemon.*			-/var/log/ha-cluster.log' >> /etc/rsyslog.conf

WORKDIR /root
