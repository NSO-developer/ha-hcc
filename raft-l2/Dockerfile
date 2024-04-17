ARG NSO_VERSION
FROM cisco-nso-prod:${NSO_VERSION}
RUN dnf --disableplugin subscription-manager install -y openssh-server net-tools rsyslog \
    && groupadd ncsadmin \
    && useradd --create-home --home-dir /home/admin --no-user-group --no-log-init --groups ncsadmin --shell /bin/bash admin \
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
