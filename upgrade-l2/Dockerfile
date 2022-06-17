FROM debian:11-slim

ARG NSO_VERSION
ARG NEW_NSO_VERSION
ARG HCC_VERSION
ARG NEW_HCC_VERSION
ARG APP_NAME
ARG NODE3_NAME

ENV NSO_VERSION=${NSO_VERSION}
ENV NEW_NSO_VERSION=${NEW_NSO_VERSION}
ENV HCC_VERSION=${HCC_VERSION}
ENV NEW_HCC_VERSION=${NEW_HCC_VERSION}
ENV APP_NAME=${APP_NAME}
ENV DEBIAN_FRONTEND=noninteractive
ENV NCS_ROOT_DIR=/opt/ncs
ENV NCS_DIR=/opt/ncs/current
ENV NCS_CONFIG_DIR=/etc/ncs
ENV NCS_RUN_DIR=/var/opt/ncs
ENV NCS_LOG_DIR=/var/log/ncs
ENV LD_LIBRARY_PATH=/opt/ncs/current/lib
ENV PYTHONPATH=/opt/ncs/current/src/ncs/pyapi
ENV PATH=/opt/ncs/current/bin:$PATH

COPY nso-${NSO_VERSION}.linux.x86_64.installer.bin /home/admin/${APP_NAME}/
COPY nso-${NEW_NSO_VERSION}.linux.x86_64.installer.bin /home/admin/${APP_NAME}/
WORKDIR /home/admin/${APP_NAME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends libxml2-utils xsltproc \
       default-jre python3-pip python3-setuptools libssl-dev openssh-client \
       make libcap2-bin iproute2 gawk arping sudo nano traceroute \
       iputils-ping net-tools openssh-server \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && groupadd ncsadmin \
    && useradd --create-home --home-dir /home/admin --no-user-group \
       --no-log-init --groups ncsadmin --shell /bin/bash admin \
    && mkdir /home/admin/.ssh \
    && mkdir /var/run/sshd \
    && ssh-keygen -N "" -t ed25519 -m pem -f /home/admin/.ssh/id_ed25519 \
    && chmod +x /home/admin/${APP_NAME}/nso-${NSO_VERSION}.linux.x86_64.installer.bin \
       /home/admin/${APP_NAME}/nso-${NEW_NSO_VERSION}.linux.x86_64.installer.bin \
    && /home/admin/${APP_NAME}/nso-${NSO_VERSION}.linux.x86_64.installer.bin --system-install \
       --run-as-user admin --non-interactive \
    && /home/admin/${APP_NAME}/nso-${NEW_NSO_VERSION}.linux.x86_64.installer.bin --system-install \
       --run-as-user admin --non-interactive \
          && chown root ${NCS_ROOT_DIR}/ncs-${NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && chmod u+s ${NCS_ROOT_DIR}/ncs-${NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && chown root ${NCS_ROOT_DIR}/ncs-${NEW_NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && chmod u+s ${NCS_ROOT_DIR}/ncs-${NEW_NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && setcap CAP_NET_ADMIN=+eip /bin/ip \
    && setcap CAP_NET_RAW=+eip /usr/sbin/arping \
    && echo "admin ALL = (root) NOPASSWD: /var/opt/ncs/state/packages-in-use/1/tailf-hcc/priv/vipctl" >> /etc/sudoers \
    && echo "admin ALL = (root) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers \
    && sed -i.bak -e "s/#PasswordAuthentication yes/PasswordAuthentication no/" \
                  -e "s/#PubkeyAuthentication yes/PubkeyAcceptedKeyTypes ssh-ed25519/" \
                  /etc/ssh/sshd_config \
    && apt-get autoremove -y \
    && apt-get clean

ADD ${APP_NAME}.tar.gz /home/admin/
COPY ncs-${NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz /home/admin/${APP_NAME}/package-store/
COPY ncs-${NEW_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz /home/admin/${APP_NAME}/package-store/
RUN chown -Rh admin:ncsadmin /home/admin ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} \
    ${NCS_LOG_DIR} \
    && chmod -R 755 /home/admin \
    && chmod -R 755 ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} ${NCS_LOG_DIR} \
    && chown admin:ncsadmin ${NCS_ROOT_DIR} \
    && chmod 755 ${NCS_ROOT_DIR} \
    && mv /home/admin/${APP_NAME}/*token*.sh ${NCS_RUN_DIR}/scripts/ \
    && mv /home/admin/${APP_NAME}/${NODE3_NAME}_key.pub /home/admin/.ssh/authorized_keys \
    && chmod 700 /home/admin/.ssh \
    && chmod 600 /home/admin/.ssh/id_ed25519.pub \
    && chmod 600 /home/admin/.ssh/id_ed25519 \
    && chmod 600 /home/admin/.ssh/authorized_keys

USER admin:ncsadmin
CMD [ "./run.sh" ]
