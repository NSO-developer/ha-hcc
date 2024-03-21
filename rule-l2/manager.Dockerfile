FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt install -y --no-install-recommends net-tools openssh-client xxd \
    iputils-ping iproute2 rsyslog \
    && sed -i.bak -e 's/#module(load="imtcp")/module(load="imtcp")/' \
                  -e 's|#input(type="imtcp" port="514")|input(type="imtcp" port="514")|' \
                  -e '/imklog/s/^/#/' \
                  /etc/rsyslog.conf \
    && echo 'daemon.*			-/var/log/ha-cluster.log' >> /etc/rsyslog.conf

WORKDIR /root
