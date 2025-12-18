An NSO Tail-f HCC Layer-2 Raft HA Example Setup
===============================================

This example implementation is described by the NSO Administration Guide
chapter "Tail-f HCC Package" under "Tail-f HCC Usage".
For details on the Tail-f HCC package, see the NSO Administration Guide.
While this example use containers it is not intended as a guide to running
NSO in containers. See the Containerized NSO chapter in the NSO Administration
Guide for guidance.

Example Network Overview
------------------------

- manager: SSH client to manage the paris1, paris2, and paris3 nodes
- paris1:   NSO, Tail-f HCC package (uses arping and iproute2 utils)
- paris2:  NSO, Tail-f HCC package (uses arping and iproute2 utils)
- paris3:  NSO, Tail-f HCC package (uses arping and iproute2 utils)


      --------------------  docker 0 default bridge  -------------------
                                       |
                                       | .1
      --------------------  raft-l2_NSO-net bridge  --------------------
            |                 |                |               |
            |                 |                |               |
                                 192.168.23.0/16
            |                 |                |               |
            | .97             | .2             | .98           | .99
         +----------+     +----------+     +----------+     +----------+
         |  paris3  |     | manager  |     |  paris2  |     |  paris1  |
         +----------+     +----------+     +----------+     +----------+

Prerequisites
-------------

- `NSO_VERSION` >= 6.6
- NSO production container: `cisco-nso-prod:${NSO_VERSION}`
- `ncs-${HCC_NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz`
- Docker installed

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
5. Connect to the paris1-3 shell to examine the Linux kernel route status.

        $ docker exec -it paris1.fra bash
        $ ip address show dev eth0
        $ arp -a
        $ exit

6. Examine the setup.sh -> compose.yaml -> common-services.yml ->
   manager.Dockerfile -> Dockerfile -> raft-etc/demo_setup.sh ->
   raft-etc/demo.sh files.
7. Cleanup

        $ ./teardown.sh

Implementation Details
----------------------

This demo uses Docker containers to set up the Tail-f HCC NSO package in layer 2
mode with NSO and its dependencies as described in the NSO Administration Guide
chapter "Tail-f HCC Package". The steps for the paris nodes described by the
documentation are implemented by the setup.sh, compose.yaml,
common-services.yml, manager.Dockerfile, Dockerfile, and demo_setup.sh files.

The paris container nodes use the NSO production container while a simple
manager container for Docker host access through the VIP address uses a Debian
distribution.

Further Reading
---------------

+ NSO Administrator Guide: NSO HA Raft & Tail-f HCC Package
+ examples.ncs/high-availability examples
+ https://github.com/ThomasHabets/arping
+ https://wiki.linuxfoundation.org/networking/iproute2
+ https://docs.docker.com/compose/
