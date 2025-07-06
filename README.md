# Home Infrastructure

This repo tracks the configuration used to drive my home systems.


## Physical Infrastructure

A 3 node proxmox cluster of a variety of different hardware origins. Broadly these fulfil the roles of:
* __taco__: router
* __churro__: Compute
* __mole__: NAS

## K3S cluster

Most services run on a local K3S cluster.
This is a light-weight way for me to play with Kubernetes, because I like over-engineering things!

There are 3 master nodes (one per physical instance) for the control plane.
These VMs are relatively light weight and additional agent virtual machines are run on Churro for actual workloads.

This repository uses [ Flux ](https://github.com/fluxcd/flux2) to keep this repository in sync with the
state of the deployment.
Flux queries the GitHub repository periodically and pulls in any changes as needed.

### Persistant Storage

For persistant storage, [Rook Ceph](https://rook.io/) is used to create a distributed Ceph cluster across all of the nodes.
This represents a relatively small cluster, but is suitable for my needs.
For larger storage volumes, I'll plan to use NFS mounts.

