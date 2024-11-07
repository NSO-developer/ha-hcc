# Tail-f HCC Package Examples

This repository contains variants of Tail-f HCC package HA examples as
a reference in support of the NSO documentation. See the subfolder READMEs for
details on each example.

- raft-l2 and rule-l2:
  Scripted example implementations for the example setup described by the NSO
  Administration Guide chapter "Tail-f HCC Package" under "Usage" "Layer-2
  Deployment". In addition to a shell script using the NSO CLI, a Python script
  variant using the NSO RESTCONF interface is also available.
- raft-l3bgp and rule-l3bgp:
  Scripted example implementations for the example setup described by the NSO
  Administration Guide chapter "Tail-f HCC Package" under "Usage" "Enabling
  Layer-3 BGP". In addition to a shell script using the NSO CLI, a Python
  script variant using the NSO RESTCONF interface is also available.
- raft-upgrade-l2 and rule-upgrade-l2:
  Scripted example implementations of the setup described by the NSO
  Administration Guide chapter NSO Deployment showcasing installation of NSO,
  the initial configuration of NSO, upgrade of NSO, and upgrade of NSO packages
  on the two NSO-enabled nodes. In addition to a shell script using the NSO
  CLI, a Python script variant using the NSO RESTCONF interface is also
  available.