SHELL := /bin/bash # Use bash syntax

define init_xml
	printf "<config xmlns=\"http://tail-f.com/ns/config/1.0\">\n\
	<high-availability xmlns=\"http://tail-f.com/ns/ncs\">\n\
		<token>super-secret</token>\n\
		<ha-node>\n\
			<id>$(1)</id>\n\
			<address>$(2)</address>\n\
			<nominal-role>$(6)</nominal-role>\n\
		</ha-node>\n\
		<ha-node>\n\
			<id>$(3)</id>\n\
			<address>$(4)</address>\n\
			<nominal-role>$(7)</nominal-role>\n\
			<failover-$(6)>true</failover-$(6)>\n\
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

all:
	cd package-store ; \
	ncs-make-package --service-skeleton template --dest dummy-1.0 --build --no-test --root-container dummies dummy ; \
	tar cvfz dummy-1.0.tar.gz dummy-1.0 ; \
	rm -rf dummy-1.0 ; \
	sed -i.bak -e "s|<ncs-ipc-access-check>|<ncs-ipc-address><ip>0.0.0.0</ip></ncs-ipc-address><ncs-ipc-access-check>|"\
	           -e "s|<ha>.*</ha>||"\
			   -e "s|</ncs-config>|<ha><enabled>true</enabled><ip>0.0.0.0</ip></ha></ncs-config>|"\
			   -e "s|</cli>|<style>c</style></cli>|"\
			   -e "s|</webui>|\ \ <server-name>${NSO_VIP_NAME}</server-name>\n\
\ \ \ \ <match-host-name>true</match-host-name>\n\
\ \ </webui>|" \
			   -e '/<ssh>/!b;n;c<enabled>true</enabled>'\
			   ${NCS_CONFIG_DIR}/ncs.conf ; \
	$(call init_xml,${NODE1_NAME},${NODE1_IP},${NODE2_NAME},${NODE2_IP},${NSO_VIP},${PRIMARY},${SECONDARY}) > ${NCS_RUN_DIR}/cdb/init.xml
	cp package-store/dummy-1.0.tar.gz ${NCS_RUN_DIR}/packages ; \
	cp package-store/ncs-*-tailf-hcc-*.tar.gz ${NCS_RUN_DIR}/packages

hcc-fix:
	cd package-store ; \
	tar xfz $(HCC_TARBALL_NAME) ; \
	sed -i.bak -e 's/ip address/sudo ip address/g' tailf-hcc/priv/vipctl ; \
	sed -i.bak -e 's/arping -q/sudo arping -q/g' tailf-hcc/priv/vipctl ; \
	sed -i.bak -e 's/"sudo "/""/' tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	sed -i.bak -e 's/sudo() ++ //' tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	sed -i.bak -e 's/sudo(), //' tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	${NCS_DIR}/bin/erlc -I ${NCS_DIR}/erlang/econfd/include -o tailf-hcc/erlang-lib/tailf_hcc/ebin tailf-hcc/erlang-lib/tailf_hcc/src/tailf_hcc_server.erl ; \
	tar cfz $(HCC_TARBALL_NAME) tailf-hcc ; \
	rm -rf tailf-hcc

clean:
	-rm -rf ${NCS_LOG_DIR}/* ${NCS_RUN_DIR}/packages/* ${NCS_RUN_DIR}/backups/* ${NCS_RUN_DIR}/cdb/init.xml ${NCS_RUN_DIR}/cdb/*.cdb  ${NCS_RUN_DIR}/scripts/* ${NCS_RUN_DIR}/state/* ${NCS_RUN_DIR}/streams/* ${NCS_RUN_DIR}/rollbacks/*
	-mv ${NCS_CONFIG_DIR}/ncs.conf.bak ${NCS_CONFIG_DIR}/ncs.conf

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
