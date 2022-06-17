SHELL := /bin/bash # Use bash syntax

define init_xml
	printf "<config xmlns=\"http://tail-f.com/ns/config/1.0\">\n\
	<high-availability xmlns=\"http://tail-f.com/ns/ncs\">\n\
		<token>super-secret</token>\n\
		<ha-node>\n\
			<id>$(1)</id>\n\
			<address>$(2)</address>\n\
			<nominal-role>master</nominal-role>\n\
		</ha-node>\n\
		<ha-node>\n\
			<id>$(3)</id>\n\
			<address>$(4)</address>\n\
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
		<vip-address>$(5)</vip-address>\n\
	</hcc>\n\
</config>"
endef

all: packages
	sed -i.orig -e "s|<ncs-ipc-access-check>|<ncs-ipc-address><ip>0.0.0.0</ip></ncs-ipc-address><ncs-ipc-access-check>|" \
							-e "s|</restconf>|<token-response><x-auth-token>true</x-auth-token></token-response></restconf>|" \
							-e "s|</aaa>|<external-validation><enabled>true</enabled><executable>${NCS_RUN_DIR}/scripts/token_auth.sh</executable></external-validation></aaa>|" \
							-e "s|<ha>.*</ha>||" \
						 	-e "s|</ncs-config>|<ha><enabled>true</enabled><ip>0.0.0.0</ip></ha></ncs-config>|"  \
						 	-e 's|</cli>|<style>c</style></cli>|' \
						 	-e 's|@ncs|@nso-\\\H|g' \
						 	-e '/<ssh>/!b;n;c<enabled>true</enabled>' \
						 	${NCS_CONFIG_DIR}/ncs.conf ; \
	sed -i.bak -e '/<ssl>/!b;n;c<enabled>true</enabled>' \
						 ${NCS_CONFIG_DIR}/ncs.conf ; \
	$(call init_xml,${NODE1_NAME},${NODE1_IP},${NODE2_NAME},${NODE2_IP},${NSO_VIP}) > ${NCS_RUN_DIR}/cdb/init.xml

packages:
	cd package-store ; \
	rm dummy* inert* tokens*; \
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
	ncs-make-package --service-skeleton template --dest inert-1.0 --build --no-test --root-container inerts inert ; \
	tar cvfz inert-1.0.tar.gz inert-1.0 ; \
	rm -rf inert-1.0 ; \
	ncs-make-package --service-skeleton template --dest dummy-1.1 --no-test --root-container dummies dummy ; \
	rm -rf dummy-1.1/templates/* ; \
	sed -i.bak -e "s/1.0/1.1/g" dummy-1.1/package-meta-data.xml ; \
	cp ../yang/dummy.yang dummy-1.1/src/yang/dummy.yang ; \
	sed -i.bak -e "s%// replace with your own stuff here%leaf description {type string;}%" \
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

clean:
	-rm -rf ${NCS_LOG_DIR}/* ${NCS_RUN_DIR}/packages/* ${NCS_RUN_DIR}/backups/* ${NCS_RUN_DIR}/cdb/init.xml ${NCS_RUN_DIR}/cdb/*.cdb ${NCS_RUN_DIR}/state/* ${NCS_RUN_DIR}/streams/* ${NCS_RUN_DIR}/rollbacks/*
	-cp -f ${NCS_CONFIG_DIR}/ncs.conf.orig ${NCS_CONFIG_DIR}/ncs.conf

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
