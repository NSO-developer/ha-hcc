FROM debian:11-slim

ARG NSO_VERSION
ARG TAILF_HCC_VERSION
ARG APP_NAME

ENV DEBIAN_FRONTEND=noninteractive
ENV NCS_DIR=/opt/ncs/current
ENV NCS_CONFIG_DIR=/etc/ncs
ENV NCS_RUN_DIR=/var/opt/ncs
ENV NCS_LOG_DIR=/var/log/ncs
ENV LD_LIBRARY_PATH=/opt/ncs/current/lib
ENV PYTHONPATH=/opt/ncs/current/src/ncs/pyapi
ENV PATH=/opt/ncs/current/bin:$PATH
ENV NSO_VERSION=${NSO_VERSION}
ENV TAILF_HCC_VERSION=${TAILF_HCC_VERSION}
ENV APP_NAME=${APP_NAME}

COPY nso-${NSO_VERSION}.linux.x86_64.installer.bin /tmp
WORKDIR /tmp

RUN mkdir -p /usr/share/man/man1 \
    && apt-get update \
    && apt-get install -y --no-install-recommends libxml2-utils xsltproc \
       default-jre python3-pip python3-setuptools libssl-dev openssh-client \
       make libcap2-bin iproute2 gawk arping gobgpd sudo nano traceroute \
       iputils-ping net-tools \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && groupadd ncsadmin \
    && useradd --create-home --home-dir /home/admin --no-user-group \
       --no-log-init --groups ncsadmin --shell /bin/bash admin \
    && echo "admin:admin" | chpasswd \
    && chmod +x /tmp/nso-${NSO_VERSION}.linux.x86_64.installer.bin \
    && /tmp/nso-${NSO_VERSION}.linux.x86_64.installer.bin --system-install \
       --run-as-user admin --non-interactive \
    && setcap CAP_NET_BIND_SERVICE=+ep /usr/bin/gobgpd \
    && setcap CAP_NET_ADMIN=+ep /bin/ip \
    && echo "admin ALL = (root) NOPASSWD: /bin/ip" >> /etc/sudoers \
    && echo "admin ALL = (root) NOPASSWD: /opt/ncs/current/lib/ncs/bin/arping" >> /etc/sudoers \
    && apt-get autoremove -y \
    && apt-get clean

ADD ${APP_NAME}.tar.gz /home/admin/
COPY ncs-${NSO_VERSION}-tailf-hcc-${TAILF_HCC_VERSION}.tar.gz /home/admin/${APP_NAME}/package-store/
RUN chmod -R 755 /home/admin ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} ${NCS_LOG_DIR} \
    && chown -R admin:ncsadmin /home/admin ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} \
       ${NCS_LOG_DIR}

USER admin:ncsadmin
WORKDIR /home/admin/${APP_NAME}
CMD [ "./run.sh" ]
