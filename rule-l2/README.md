An NSO Tail-f HCC Layer-2 Rule Based HA Example Setup
=====================================================

This example implementation is described by the NSO Administration Guide
chapter "Tail-f HCC Package" under "Tail-f HCC Usage".
For details on the Tail-f HCC package, see the NSO Administration Guide.
While this example use containers it is not intended as a guide to running
NSO in containers. See the Containerized NSO chapter in the NSO Administration
Guide for guidance.

Example Network Overview
------------------------

- manager: SSH client to manage the paris and london nodes
- paris:   NSO, Tail-f HCC package (uses arping and iproute2 utils)
- london:  NSO, Tail-f HCC package (uses arping and iproute2 utils)

      ----------  docker 0 default bridge  ----------
                              |
                              | .1
      -----------  rule-l2_NSO-net bridge  ----------
            |                 |                |
            |                 |                |
                        192.168.23.0/16
            |                 |                |
            | .98             | .2             | .99
      +----------+     +----------+     +----------+
      | london   |     | manager  |     | paris    |
      +----------+     +----------+     +----------+

Prerequisites
-------------

- `NSO_VERSION` >= 6.5
- NSO production container: `cisco-nso-prod:${NSO_VERSION}`
- `ncs-${HCC_NSO_VERSION}-tailf-hcc-${HCC_VERSION}.tar.gz`
- Docker installed

Running the Example
-------------------

1. Load the NSO production container image using Docker and add Tail-f HCC
   package into the ./rule-etc directory. If necessary, change the version
   number NSO_VERSION, HCC_NSO_VERSION, and HCC_VERSION variables in the
   setup.sh file.
2. Run the setup.sh script:

        $ ./setup.sh

   This will start the manager and nodes running NSO using Docker Compose.
3. Press a key to run a demo from the manager node.
4. Press a key to follow the logs from the manager and NSO nodes. Hit ctrl-c.
5. Connect to the london and paris shell to examine the Linux kernel route
   status.

        $ docker exec -it paris.fra bash
        $ ip address show dev eth0
        $ arp -a
        $ exit

6. Examine the setup.sh -> compose.yaml -> common-services.yml ->
   manager.Dockerfile -> Dockerfile -> rule-etc/demo_setup.sh ->
   rule-etc/demo.sh files.
7. Cleanup

        $ ./teardown.sh

Implementation Details
----------------------

This demo uses Docker containers to set up the Tail-f HCC NSO package in layer 2
mode with NSO and its dependencies as described in the NSO Administration Guide
chapter "Tail-f HCC Package". The steps for the paris and london nodes
described by the documentation are implemented by the setup.sh, compose.yaml, common-services.yml, manager.Dockerfile, Dockerfile, and
demo_setup.sh files.

The paris and london container nodes use the NSO production container while a
simple manager container for Docker host access through the VIP address uses
a Debian distribution.

Further Reading
---------------

+ NSO Administrator Guide: NSO rule-based HA & Tail-f HCC Package
+ examples.ncs/development-guide/high-availability examples
+ https://github.com/ThomasHabets/arping
+ https://wiki.linuxfoundation.org/networking/iproute2
+ https://docs.docker.com/compose/
