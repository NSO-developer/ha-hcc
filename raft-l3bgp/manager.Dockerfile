FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends dnsutils net-tools nftables \
    openssh-client iputils-ping iproute2 frr openssl libssl-dev rsyslog \
    openssl \
    && sed -i.bak -e 's/#module(load="imtcp")/module(load="imtcp")/' \
                  -e 's|#input(type="imtcp" port="514")|input(type="imtcp" port="514")|' \
                  -e '/imklog/s/^/#/' \
                  /etc/rsyslog.conf \
    && echo 'daemon.*			-/var/log/ha-cluster.log' >> /etc/rsyslog.conf

WORKDIR /root
