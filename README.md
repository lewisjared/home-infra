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

This repository uses [ Flux ](https://github.com/fluxcd/flux2) to keep this repository in sync with the
state of the deployment.
Flux queries the girhub repository periodically and pulls in any changes as needed.


