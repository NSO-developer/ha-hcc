SHELL := /bin/bash # Use bash syntax

define ha_init_xml
  printf "<config xmlns=\"http://tail-f.com/ns/config/1.0\">\n\
  <high-availability xmlns=\"http://tail-f.com/ns/ncs\">\n\
    <token>$(1)</token>\n\
    <ha-node>\n\
      <id>$(2)</id>\n\
      <address>$(3)</address>\n\
      <nominal-role>master</nominal-role>\n\
    </ha-node>\n\
    <ha-node>\n\
      <id>$(4)</id>\n\
      <address>$(5)</address>\n\
      <nominal-role>slave</nominal-role>\n\
      <failover-master>true</failover-master>\n\
    </ha-node>\n\
    <settings>\n\
      <start-up>\n\
        <assume-nominal-role>true</assume-nominal-role>\n\
        <join-ha>true</join-ha>\n\
      </start-up>\n\
      <enable-failover>true</enable-failover>\n\
      <reconnect-interval>5</reconnect-interval>\n\
      <reconnect-attempts>3</reconnect-attempts>\n\
    </settings>\n\
  </high-availability>\n\
  <hcc xmlns=\"http://cisco.com/pkg/tailf-hcc\">\n\
    <enabled>true</enabled>\n\
    <vip-address>$(6)</vip-address>\n\
  </hcc>\n\
</config>"
endef

define globs_init_xml
  printf "<config xmlns=\"http://tail-f.com/ns/config/1.0\">\n\
  <devices xmlns=\"http://tail-f.com/ns/ncs\">\n\
    <global-settings>\n\
      <connect-timeout>120</connect-timeout>\n\
      <read-timeout>120</read-timeout>\n\
      <write-timeout>120</write-timeout>\n\
      <trace-dir>$(1)</trace-dir>\n\
    </global-settings>\n\
  </devices>\n\
  <services xmlns=\"http://tail-f.com/ns/ncs\">\n\
    <global-settings>\n\
      <service-callback-timeout>180</service-callback-timeout>\n\
    </global-settings>\n\
  </services>\n\
</config>"
endef

all: packages
	sed -i.orig -e 's|</restconf>|\ \ <token-response>\
\ \ \ \ \ \ <x-auth-token>true</x-auth-token>\
\ \ \ \ </token-response>\
\ \ </restconf>|' \
							-e "s|</aaa>|\ \ <external-validation>\n\
\ \ \ \ \ \ <enabled>true</enabled>\n\
\ \ \ \ \ \ <executable>${NCS_RUN_DIR}/scripts/token_auth.sh</executable>\n\
\ \ \ \ </external-validation>\n\
\ \ </aaa>|" \
							-e "s|<ha>.*</ha>||" \
							-e "s|</ncs-config>|\ \ <ha>\n\
\ \ \ \ <enabled>true</enabled>\n\
\ \ \ \ <ip>${NODE_IP}</ip>\n\
\ \ </ha>\n\
</ncs-config>|"  \
							-e 's|</cli>|\ \ <style>c</style>\
\ \ </cli>|' \
							-e 's|@ncs|@nso-\\\H|g' \
							-e '/<ssh>/!b;n;c<enabled>true</enabled>' \
							${NCS_CONFIG_DIR}/ncs.conf ; \
	sed -i.bak -e '/<ssl>/!b;n;c<enabled>true</enabled>' \
						 ${NCS_CONFIG_DIR}/ncs.conf ; \
	sed -i.bak -e '/<cgi>/!b;n;c<enabled>false</enabled>' \
						 ${NCS_CONFIG_DIR}/ncs.conf ; \
	sed -i.orig '/<group>ncsoper<\/group>/a\
\ \ \ \ \ \ <rule>\
\ \ \ \ \ \ \ \ <name>generate-token<\/name>\
\ \ \ \ \ \ \ \ <rpc-name>generate-token<\/rpc-name>\
\ \ \ \ \ \ \ \ <action>permit<\/action>\
\ \ \ \ \ \ <\/rule>' ${NCS_RUN_DIR}/cdb/aaa_init.xml ; \
	$(call ha_init_xml,${HA_TOKEN},${NODE1_NAME},${NODE1_IP},${NODE2_NAME},${NODE2_IP},${NSO_VIP}) > ${NCS_RUN_DIR}/cdb/ha_init.xml
	$(call globs_init_xml,${NCS_LOG_DIR}) > ${NCS_RUN_DIR}/cdb/globs_init.xml

packages:
	cd package-store ; \
	rm -f dummy* inert* tokens*; \
	ncs-make-package --service-skeleton template --dest token-1.0 --no-test --root-container tokens token ; \
	rm -rf token-1.0/templates/* ; \
	cp ../yang/token.yang token-1.0/src/yang/token.yang ; \
	make -C token-1.0/src clean all ; \
	tar cvfz token-1.0.tar.gz token-1.0 ; \
	rm -rf token-1.0 ; \
	ncs-make-package --service-skeleton template --dest dummy-1.0 --no-test --root-container dummies dummy ; \
	rm -rf dummy-1.0/templates/* ; \
	cp ../yang/dummy.yang dummy-1.0/src/yang/dummy.yang ; \
	make -C dummy-1.0/src clean all ; \
	tar cvfz dummy-1.0.tar.gz dummy-1.0 ; \
	rm -rf dummy-1.0 ; \
	ncs-make-package --service-skeleton python-and-template --dest inert-1.0 --build --no-test --root-container inerts inert ; \
	tar cvfz inert-1.0.tar.gz inert-1.0 ; \
	rm -rf inert-1.0 ; \
	ncs-make-package --service-skeleton template --dest dummy-1.1 --no-test --root-container dummies dummy ; \
	rm -rf dummy-1.1/templates/* ; \
	sed -i.bak -e "s/1.0/1.1/g" dummy-1.1/package-meta-data.xml ; \
	cp ../yang/dummy.yang dummy-1.1/src/yang/dummy.yang ; \
	sed -i.bak -e "s|// replace with your own stuff here|leaf description {type string;}|" \
	           dummy-1.1/src/yang/dummy.yang ; \
	make -C dummy-1.1/src clean all ; \
	tar cvfz dummy-1.1.tar.gz dummy-1.1 ; \
	rm -rf dummy-1.1

rebuild-packages:
	cd package-store ; \
	tar xvfz token-1.0.tar.gz ; \
	make -C token-1.0/src clean all ; \
	tar cvfz token-1.0.tar.gz token-1.0 ; \
  rm -rf token-1.0 ; \
	tar xvfz dummy-1.0.tar.gz ; \
	make -C dummy-1.0/src clean all ; \
	tar cvfz dummy-1.0.tar.gz dummy-1.0 ; \
	rm -rf dummy-1.0 ; \
	tar xvfz inert-1.0.tar.gz ; \
	make -C inert-1.0/src clean all ; \
	tar cvfz inert-1.0.tar.gz inert-1.0 ; \
	rm -rf inert-1.0 ; \
	tar xvfz dummy-1.1.tar.gz ; \
	make -C dummy-1.1/src clean all ; \
	tar cvfz dummy-1.1.tar.gz dummy-1.1 ; \
	rm -rf dummy-1.1

hcc-fix:
	cd /${APP_NAME}/package-store ; \
	tar xfz $(HCC_TARBALL_NAME) ; \
	sed -i.bak -e 's/ip address/sudo ip address/g' tailf-hcc/priv/vipctl ; \
	sed -i.bak -e 's/"sudo "/""/' tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	${NCS_DIR}/bin/erlc -I ${NCS_DIR}/erlang/econfd/include -o tailf-hcc/erlang-lib/tailf_hcc/ebin tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	tar cfz $(HCC_TARBALL_NAME) tailf-hcc ; \
	rm -rf tailf-hcc

clean:
	-rm -rf ${NCS_LOG_DIR}/* ${NCS_RUN_DIR}/packages/* ${NCS_RUN_DIR}/backups/* ${NCS_RUN_DIR}/cdb/init.xml ${NCS_RUN_DIR}/cdb/*.cdb ${NCS_RUN_DIR}/state/* ${NCS_RUN_DIR}/streams/* ${NCS_RUN_DIR}/rollbacks/*
	-cp -f ${NCS_CONFIG_DIR}/ncs.conf.orig ${NCS_CONFIG_DIR}/ncs.conf
	-cp -f ${NCS_RUN_DIR}/cdb/aaa_init.xml.orig ${NCS_RUN_DIR}/cdb/aaa_init.xml

start:
	if [ $(shell whoami) = "root" ] ; then \
		/etc/init.d/ncs start ; \
	else \
		ncs --cd ${NCS_RUN_DIR} --heart -c ${NCS_CONFIG_DIR}/ncs.conf ; \
	fi

stop:
	-/etc/init.d/ncs stop

cli:
	ncs_cli -u admin -g ncsadmin

cli2:
	ncs_cli -u admin -g ncsadmin -C
