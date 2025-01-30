An NSO Tail-f HCC Combined Layer-2 and Layer-3 BGP Example Setup
================================================================

This example implementation is described by the NSO Administration Guide
chapter "Tail-f HCC Package" under "Tail-f HCC Usage".
For details on the Tail-f HCC package, see the NSO Administration Guide.
While this example use containers it is not intended as a guide to running
NSO in containers. See the Containerized NSO chapter in the NSO Administration
Guide for guidance.

Example Network Overview
------------------------

- manager: SSH client to manage the paris and london nodes, FRRouting Zebra + BGP
         and nftables port forwarding + NAT
- paris:  NSO, Tail-f HCC package (uses GoBGP and iproute2 utils)
- london: NSO, Tail-f HCC package (uses GoBGP and iproute2 utils)

    -------------------  docker 0 default bridge  -------------------
                                    | .1
                                    |
                              172.17.0.0/16
                                    |
                                    | .2
                          +------------------+
                          | manager          |
                          | ID: 172.17.0.2   |
                          | AS: 64514        |
                          +------------------+
                      .2 /         | .2       \ .2
                        /          |           \
            192.168.30.0/24  192.168.31.0/24   192.168.32.0/24
                      /            |             \
                  .97 /             | .98          \ .99
    +-------------------+ +-------------------+ +-------------------+
    | berlin            | | london            | | paris             |
    | ID: 192.168.30.97 | | ID: 192.168.31.98 | | ID: 192.168.32.99 |
    | AS: 64513         | | AS: 64512         | | AS: 64511         |
    +-------------------+ +-------------------+ +-------------------+

Prerequisites
-------------

- `NSO_VERSION` >= 6.1
- NSO production container: `cisco-nso-prod:${NSO_VERSION}`
- `ncs-${HCC_NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz`
- Docker installed

NOTE: nftables will not work in an x86_64 container on Apple Silicon arm64

Running the Example
-------------------

1. Load the NSO production container image using Docker and add Tail-f HCC
   package into the ./raft-etc directory. If necessary, change the version
   number NSO_VERSION, HCC_NSO_VERSION, and HCC_VERSION variables in the
   setup.sh file.
2. Run the setup.sh script:

        $ ./setup.sh

   This will start the manager and nodes running NSO using Docker Compose.
3. Press a key to run a demo from the manager node.
4. Press a key to follow the logs from the manager and NSO nodes. Hit ctrl-c.
5. Connect to the london, paris, berlin, and manager shell to examine the BGP
   and Linux kernel route status.

        $ docker exec -it paris.fra bash
        $ ip address
        $ ip route
        $ cat /tmp/bgp.*.conf
        $ gobgp global
        $ gobgp global rib
        $ gobgp neighbor
        $ exit

        $ docker exec -it manager bash
        # ip address
        # ip route
        # vtysh
        # show bgp summary
        # show ip bgp
        # show bgp neighbor
        # exit
        # exit

6. Examine the setup.sh -> compose.yaml -> common-services.yml ->
   manager.Dockerfile -> Dockerfile -> raft-etc/demo_setup.sh ->
   raft-etc/demo.sh files.
7. Cleanup

        $ ./teardown.sh

Implementation Details
----------------------

This demo uses Docker containers to set up the Tail-f HCC NSO package in layer 3
BGP mode with NSO and its dependencies as described in the NSO Administration
Guide chapter "Tail-f HCC Package". The steps for the paris, berlin, and london
nodes described by the documentation are implemented by the setup.sh,
compose.yaml, common-services.yml, manager.Dockerfile, Dockerfile, and
demo_setup.sh files.

The paris, london, and berlin container nodes use the NSO production container
while a simple manager container for Docker host access through the VIP address
uses a Debian distribution.

- The FRRouting Zebra + BGP implementation is used to set up the BGP-enabled
  manager node as described by the NSO Administration Guide.
- nftables is used for translating (NAT) the berlin, london, and paris source
  IP address to enable them to access the bridge network and forward 12024 on
  the manager node to the VIP address port 2024 of NSO.

Further Reading
---------------

+ NSO Administrator Guide: NSO HA Raft & Tail-f HCC Package
+ examples.ncs/high-availability examples
+ https://osrg.github.io/gobgp/
+ https://frrouting.org/
+ https://nftables.org/
+ https://wiki.linuxfoundation.org/networking/iproute2
+ https://docs.docker.com/compose/
