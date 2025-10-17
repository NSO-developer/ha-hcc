ARG NSO_VERSION
FROM cisco-nso-prod:${NSO_VERSION}
USER root
RUN dnf --disableplugin subscription-manager install -y openssh-server wget net-tools rsyslog \
    && groupadd ncsadmin \
    && useradd --create-home --home-dir /home/admin --no-user-group --no-log-init --groups ncsadmin --shell /bin/bash admin \
    && mkdir -p /home/admin/.ssh \
    && chmod 755 /home/admin/.ssh \
    && chown -Rh admin:ncsadmin /home/admin \
    && chmod 755 /home/admin \
    && cd /usr/bin \
    && wget https://github.com/osrg/gobgp/releases/download/v2.25.0/gobgp_2.25.0_linux_amd64.tar.gz \
    && tar xzf gobgp_2.25.0_linux_amd64.tar.gz \
    && setcap 'cap_net_bind_service=+ep' /usr/bin/gobgpd \
    && echo "nso ALL = (root) NOPASSWD"":"" /usr/sbin/ip" >> /etc/sudoers \
    && echo "nso ALL = (root) NOPASSWD: /usr/sbin/arping" >> /etc/sudoers \
    && mkdir -p /home/admin/.ssh \
    && sed -i.bak -e "s/#PasswordAuthentication yes/PasswordAuthentication no/" \
                  -e "s/PasswordAuthentication yes/PasswordAuthentication no/" \
                  -e "s/#PubkeyAuthentication yes/PubkeyAcceptedKeyTypes ssh-ed25519/" \
                  -e "s/#PermitUserEnvironment no/PermitUserEnvironment yes/" \
                  -e "s/PermitUserEnvironment no/PermitUserEnvironment yes/" \
                  -e "s|HostKey /etc/ssh/ssh_host_rsa_key|#HostKey /etc/ssh/ssh_host_rsa_key|" \
                  -e "s|HostKey /etc/ssh/ssh_host_ecdsa_key|#HostKey /etc/ssh/ssh_host_ecdsa_key|" \
                  /etc/ssh/sshd_config \
    && echo "HostKey /nso/etc/ssh/ssh_host_ed25519_key" >> /etc/ssh/sshd_config \
    && sed -i.bak -e 's/SysSock.Use="off"/SysSock.Use="on"/' \
                  -e '/imklog/s/^/#/' \
                  /etc/rsyslog.conf \
    && echo 'daemon.info		@@manager' >> /etc/rsyslog.conf \
    && echo 'daemon.*			-/var/log/daemon.log' >> /etc/rsyslog.conf