FROM redhat/ubi9:latest

ARG NSO_ARCH
ARG NSO_VERSION
ARG NCS_RUN_DIR
ARG NCS_CONFIG_DIR
ARG NCS_LOG_DIR
ARG NCS_ROOT_DIR

COPY manager-etc/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin /tmp/

RUN yum install -y python3 java-21-openjdk-devel openssh-server \
    openssl net-tools iproute iputils sudo rsyslog \
    && ln -s /usr/bin/python3 /usr/bin/python
RUN groupadd ncsadmin \
    && groupadd ncsoper \
    && useradd --create-home --home-dir /home/admin --no-user-group \
       --no-log-init --groups ncsadmin --shell /bin/bash admin \
    && useradd --create-home --home-dir /home/oper --no-user-group \
       --no-log-init --groups ncsoper --shell /bin/bash oper \
    && echo "oper:oper" | chpasswd \
    && chmod u+x /tmp/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin \
    && /tmp/nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin --system-install \
       --run-as-user admin --non-interactive \
    && echo "admin ALL = (root) NOPASSWD: /sbin/ip" >> /etc/sudoers \
    && echo "admin ALL = (root) NOPASSWD: /usr/sbin/ip" >> /etc/sudoers \
    && echo "admin ALL = (root) NOPASSWD: /opt/ncs/current/lib/ncs/bin/arping" >> /etc/sudoers \
    && echo "admin ALL = (root) NOPASSWD: /bin/arping" >> /etc/sudoers \
    && mkdir -p /home/admin/.ssh \
    && touch /home/admin/.ssh/authorized_keys \
    && mkdir -p /home/oper/.ssh \
    && touch /home/oper/.ssh/authorized_keys \
    && mkdir -p /root/.ssh \
    && touch /root/.ssh/authorized_keys \
    && sed -i.bak -e "s/#PasswordAuthentication yes/PasswordAuthentication no/" \
                  -e "s/PasswordAuthentication yes/PasswordAuthentication no/" \
                  -e "s/#PubkeyAuthentication yes/PubkeyAcceptedKeyTypes ssh-ed25519/" \
                  -e "s/#PermitUserEnvironment no/PermitUserEnvironment yes/" \
                  -e "s/PermitUserEnvironment no/PermitUserEnvironment yes/" \
                  -e "s|HostKey /etc/ssh/ssh_host_rsa_key|#HostKey /etc/ssh/ssh_host_rsa_key|" \
                  -e "s|HostKey /etc/ssh/ssh_host_ecdsa_key|#HostKey /etc/ssh/ssh_host_ecdsa_key|" \
                  /etc/ssh/sshd_config \
    && echo "DenyUsers oper" >> /etc/ssh/sshd_config \
    && sed -i.bak -e 's/SysSock.Use="off"/SysSock.Use="on"/' \
                  -e '/imklog/s/^/#/' \
                  /etc/rsyslog.conf \
    && echo 'daemon.info		@@manager' >> /etc/rsyslog.conf \
    && echo 'daemon.*			-/var/log/daemon.log' >> /etc/rsyslog.conf

RUN chown -Rh admin:ncsadmin ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} \
    ${NCS_LOG_DIR} /home/admin \
    && chmod -R g=u ${NCS_CONFIG_DIR} ${NCS_RUN_DIR} ${NCS_LOG_DIR} \
    && chown admin:ncsadmin ${NCS_ROOT_DIR} \
    && chown root ${NCS_ROOT_DIR}/ncs-${NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && chmod u+s ${NCS_ROOT_DIR}/ncs-${NSO_VERSION}/lib/ncs/lib/core/confd/priv/cmdwrapper \
    && chmod 750 /home/admin/.ssh \
    && chmod 640 /home/admin/.ssh/authorized_keys \
    && chown -R oper:ncsoper /home/oper \
    && chmod 755 /home/oper/.ssh \
    && chmod 644 /home/oper/.ssh/authorized_keys \
    && chown -R root:root /root/ \
    && chmod 700 /root/.ssh \
    && chmod 600 /root/.ssh/authorized_keys \
    && rm -f /etc/ssh/*key* /etc/ncs/ssh/*key* \
    && rm -rf /tmp/* /var/tmp/* \
    && yum autoremove -y

WORKDIR /home/admin
