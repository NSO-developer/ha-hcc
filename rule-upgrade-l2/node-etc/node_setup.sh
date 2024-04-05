#!/bin/bash
set -eu # Abort the script if a command returns with a non-zero exit code or if
        # a variable name is dereferenced when the variable hasn't been set

RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

printf "${GREEN}##### Node setup\n${NC}"
chown -Rh admin:ncsadmin /home/admin/etc
cp /home/admin/etc/ncs.conf ${NCS_CONFIG_DIR}

cat /home/admin/etc/ncs.crypto_keys > ${NCS_CONFIG_DIR}/ncs.crypto_keys

cp /home/admin/etc/ssh_host_ed25519_key* ${NCS_CONFIG_DIR}/ssh
chmod 660 ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key.pub
chmod 660 ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key
chown -Rh admin:ncsadmin ${NCS_CONFIG_DIR}/ssh/ssh_host_ed25519_key*

cat /home/admin/etc/authorized_keys >> /home/admin/.ssh/authorized_keys
cat /home/admin/etc/authorized_keys >> /home/oper/.ssh/authorized_keys
cat /home/admin/etc/upgrade_key >> /root/.ssh/authorized_keys

cp /home/admin/node-etc/gen_token.sh ${NCS_RUN_DIR}/scripts/
cp /home/admin/node-etc/token_auth.sh ${NCS_RUN_DIR}/scripts/

env /bin/bash -o posix -c 'export -p' >> /home/admin/.bash_profile
env | grep _ >> /home/admin/.pam_environment
env | grep _ >> /home/admin/.ssh/environment
env /bin/bash -o posix -c 'export -p' >> /root/.bash_profile
env | grep _ >> /root/.pam_environment
env | grep _ >> /root/.ssh/environment

# Allow the ncsoper user group to generate a token for RESTCONF authentication
if [ ! -f ${NCS_RUN_DIR}/cdb/aaa_init.xml.orig ] ; then
    sed -i.orig '/<group>ncsoper<\/group>/a\
\ \ \ \ \ \ <rule>\
\ \ \ \ \ \ \ \ <name>generate-token<\/name>\
\ \ \ \ \ \ \ \ <rpc-name>generate-token<\/rpc-name>\
\ \ \ \ \ \ \ \ <action>permit<\/action>\
\ \ \ \ \ \ <\/rule>' ${NCS_RUN_DIR}/cdb/aaa_init.xml
fi

printf "\n${PURPLE}##### Start the SSH and rsyslog daemons\n${NC}"
/usr/sbin/sshd
/usr/sbin/rsyslogd

while [ -f ${NCS_RUN_DIR}/upgrade ] ; do
     printf "${RED}#### Waiting for an upgrade to complete...\n${NC}"
     sleep 1
done

if [ "$(ls -A /home/admin/etc/package-store)" ]; then
    cp -r /home/admin/etc/package-store/* ${NCS_RUN_DIR}/packages/
    chown -R admin:ncsadmin ${NCS_RUN_DIR}/packages
    chmod -R g=u ${NCS_RUN_DIR}/packages
else
    printf "${RED}#### Package store empty!\n${NC}"
fi

printf "\n${PURPLE}##### Start NSO\n${NC}"
if [ -f ${NCS_RUN_DIR}/package_reload ] ; then
    printf "${PURPLE}#### Start NSO with package reload\n${NC}"
    runuser -m -u admin -g ncsadmin -- ${NCS_DIR}/bin/ncs --foreground -v --cd /home/admin --heart --with-package-reload -c ${NCS_CONFIG_DIR}/ncs.conf
else
    printf "${PURPLE}#### Start NSO without package reload\n${NC}"
    runuser -m -u admin -g ncsadmin -- ${NCS_DIR}/bin/ncs --foreground -v --cd /home/admin --heart -c ${NCS_CONFIG_DIR}/ncs.conf
fi
