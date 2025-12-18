An NSO HA Raft Tail-f HCC Layer-2 Deployment Example
====================================================

This example implementation is described by the NSO Administration Guide chapter
NSO Deployment.
The example show the parts that describe the installation of NSO, initial
configuration of NSO, upgrade of NSO, and upgrade of NSO packages on the paris,
london, and berlin nodes.
While this example use containers it is not intended as a guide to running
NSO in containers. See the Containerized NSO chapter in the NSO Administration
Guide for guidance.

Example Network Overview
------------------------

- manager: management station with CLI, RESTCONF, and SSH access to the paris
  nodes.
- paris1:   NSO, Tail-f HCC package (uses arping and iproute2 utils)
- paris2:  NSO, Tail-f HCC package (uses arping and iproute2 utils)
- paris3:  NSO, Tail-f HCC package (uses arping and iproute2 utils)


      --------------------  docker 0 default bridge  -------------------
                                      |
                                      | .1
      ----------------  raft-upgrade-l2_NSO-net bridge  ----------------
            |                 |                |               |
            |                 |                |               |
                                192.168.23.0/16
            |                 |                |               |
            | .97             | .2             | .98           | .99
      +----------+     +----------+     +----------+     +----------+
      |  paris1  |     | manager  |     |  paris2  |     |  paris3  |
      +----------+     +----------+     +----------+     +----------+

Prerequisites
-------------

- `NSO_VERSION` >= 6.5
- `nso-${NSO_VERSION}.linux.${NSO_ARCH}.installer.bin` and
  `nso-${NEW_NSO_VERSION}.linux.${NSO_ARCH}.installer.bin`, e.g. for NSO 6.5.2
  and 6.5.3
- `ncs-${HCC_NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz` and
  `ncs-${NEW_HCC_NSO_VERSION}-tailf-hcc-${NEW_HCC_VERSION}.tar.gz`, e.g 6.5 and
  6.5.4 (could be the same version). Example:

      $ pwd
      /Users/tailf/raft-upgrade-l2
      $ ls -1 n*
      ncs-6.5.3-tailf-hcc-6.0.6.tar.gz
      ncs-6.5.4-tailf-hcc-6.0.6.tar.gz
      nso-6.5.3.linux.x86_64.installer.bin
      nso-6.5.4.linux.x86_64.installer.bin

- Docker installed

Running the Example
-------------------

1. Add the NSO installation and Tail-f HCC packages into the ./manager-etc
   directory. Change the version number NSO_VERSION, NEW_NSO_VERSION,
   HCC_NSO_VERSION, NEW_HCC_NSO_VERSION, HCC_VERSION, and NEW_HCC_VERSION
   variables in the setup.sh file.
   Select the NSO_ARCH in the setup.sh file. The default is x86_64.
2. Run the setup.sh script:

        $ ./setup.sh

   This will start the manager and nodes running NSO using Docker Compose.
3. Press a key to run a CLI + shell script demo from the manager node.
4. Press a key to run an NSO and HCC version upgrade demo from the manager node.
5. Press a key to run an NSO packages upgrade demo from the manager node.
6. Press a key to run a Python request RESTCONF demo from the manager node.
7. Press a key to follow the logs from the manager and NSO nodes. Hit ctrl-c.
8. Connect to the paris1, paris2, and paris3 shell to examine the Linux kernel
   route status.

        $ docker exec -it paris1.fra bash
        $ ip address show dev eth0
        $ arp -a
        $ exit

9. Get the high-availability status using RESTCONF instead of CLI:

        $ docker exec -it manager bash

   Get a RESTCONF token for authentication using the CLI:

        root@manager$ ssh -l admin -p 2024 192.168.23.122
        admin@nso-paris1# generate_token
        token N6jNpjth1FHyNNy0s/VeSNGSMlhQVN5cnINPwbtrAik=
        admin@nso-paris1# exit

   Now use curl or Python requests, as the run_rc.py script does, to get
   the HA status. curl variant:

        root@manager$ curl -ki -H "X-Auth-Token: \
        N6jNpjth1FHyNNy0s/VeSNGSMlhQVN5cnINPwbtrAik=" \
        -H "Accept: application/yang-data+json" \
        https://192.168.23.122:8888/restconf/data/\
        tailf-ncs:high-availability/status
        {
          "tailf-ncs:status": {
            "mode": "leader",
            "current-id": "paris1",
            "assigned-role": "leader",
            "read-only-mode": false,
            "connected-follower": [
              {
                "id": "paris2",
                "address": "192.168.23.98"
              }
            ]
          }
        }

   Python requests variant:

        root@manager$ python3
        >>> import requests
        >>> requests.packages.urllib3.disable_warnings(\
            requests.packages.urllib3.exceptions.InsecureRequestWarning)
        >>> r = requests.get("https://192.168.23.122:8888/restconf/data/\
            tailf-ncs:high-availability/status", \
            headers={'Content-Type': 'application/yang-data+json', \
            'X-Auth-Token': 'N6jNpjth1FHyNNy0s/VeSNGSMlhQVN5cnINPwbtrAik='}, \
            verify=False)
        >>> print(r.text)
        {
          "tailf-ncs:status": {
            "mode": "leader",
            "current-id": "paris1",
            "assigned-role": "leader",
            "read-only-mode": false,
            "connected-follower": [
              {
                "id": "paris2",
                "address": "192.168.23.98"
              }
            ]
          }
        }

10. Connect to the london and paris1 shell to examine the Linux
    kernel route status.

        $ docker exec -it paris1 bash
        $ ip address show dev eth0
        $ arp -a
        $ exit

11. Examine the setup.sh -> compose.yaml -> common-services.yml ->
    manager.Dockerfile -> Dockerfile -> manager-etc/manager_setup.sh ->
    node-etc/node_setup.sh -> manager-etc/demo.sh -> manager-etc/upgrade_nso.sh
    -> manager-etc/upgrade_packages.sh -> manager-etc/demo_rc.py files.
12. Cleanup

        $ ./teardown.sh

Implementation Details
----------------------

This demo uses Docker containers to set up the Tail-f HCC NSO package in layer 2
mode with NSO and its dependencies and perform an NSO version upgrade and
package version upgrade as described in the NSO Administration Guide chapter
"Tail-f HCC Package". The steps for the paris nodes described by the
documentation are implemented by the setup.sh, compose.yaml,
common-services.yml, manager.Dockerfile, Dockerfile,
manager-etc/manager_setup.sh, node-etc/node_setup.sh, manager-etc/demo.sh,
manager-etc/upgrade_nso.sh, manager-etc/upgrade_packages.sh, and
manager-etc/demo_rc.py files.

NSO is installed by and started in the context of an "admin" user that belongs
to the "ncsadmin" user group. sudo is installed as the Tail-f HCC
implementation requires sudo when running the "ip" command in a non-root
context. Linux capabilities such as network admin are added to containers and
specific commands to allow running them in the context of the admin user. See
the compose.yaml, common-services.yml and Dockerfile files for details.

SSH to the paris nodes for shell and NSO CLI accces use public key-based
authentication/login, while RESTCONF uses token validation for authentication.
Tokens are retrieved through the NSO CLI that uses a shell script to generate a
token. Password authentication has been disabled for the paris nodes.

On the paris nodes, the NSO ncs, developer, audit, netconf, snmp, and
webui-access logs are configured in $NCS_CONFIG_DIR/ncs.conf to go to a
local syslog with the daemon facility managed by rsyslogd. rsyslogd pass the
logs to a local /var/log/daemon.log and send logs with log level info or higher
over TCP to the manager node's joint /var/log/daemon.log. See the rsyslogd
config file under /etc/rsyslogd.conf for details on the rsyslogd setup on the
paris and manager nodes.

Further Reading
---------------

+ NSO Administrator Guide: NSO Deployment, NSO Raft HA, and Tail-f HCC
  Package
+ examples.ncs/development-guide/high-availability examples
+ https://github.com/ThomasHabets/arping
+ https://wiki.linuxfoundation.org/networking/iproute2
+ https://docs.docker.com/compose/
+ https://www.rsyslog.com/
