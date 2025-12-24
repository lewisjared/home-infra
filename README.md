# Home Infrastructure

This repo tracks the configuration used to drive my home systems.

What I'll use this for, who knows!

## Physical Infrastructure

A 5 node proxmox (v9) cluster of a variety of different hardware origins.

| hostname | purpose | IP          | RAM   | Storage                             | Network                   |
| :------- | :------ | :---------- | ----- | :---------------------------------- | ------------------------- |
| taco     | Router  | 10.10.10.12 | 16 GB | 256GB NVMe                          | 4 x 2.5GbE                |
| churro   | Compute | 10.10.10.10 | 96 GB | 1TB NVMe                            | 2 x 2.5GbE                |
| tamale   | Compute | 10.10.10.13 | 64 GB | 1TB NVMe                            | 2 x 2.5GbE + 2 x 10G SFP+ |
| nacho    | Compute | 10.10.10.14 | 64 GB | 1TB NVMe                            | 2 x 2.5GbE + 2 x 10G SFP+ |
| mole     | Storage | 10.10.10.11 | 64 GB | 256GB NVMe , 4TB NVMe, 3 x 16TB HDD | GbE + 2.5GbE              |

### Potential upgrades

I would love to eventually swap `mole` out with a 45 drives-style chassis.
The networking for Mole leaves a bit to be desired.

## Network

The current default subnet is 10.16.0.0/24,
but I'm migrating over to use VLANs (10.10.xx.0/16) to segment traffic.
This is a little dependent on new hardware to do this properly as the 2.5GbE switch is unmanaged.

The compute and storage are interconnected via a 10GbE switch (10.10.10.2).
These nodes run kubernetes so there is a lot of east-west traffic between them that doesn't need to hit the router.

```mermaid
graph TD
    %% Devices
    INET[Internet]
    curro
    switch-10G
    switch-2.5G[switch-2.5G (Unmanaged)]
    Office
    Lounge
    TV

    AP1[UniFi AP #1]
    AP2[UniFi AP #2]

    %% WAN
    INET --- curro

    %% Gateway LAN to core
    curro ---|2.5G| switch-2.5G

    %% Servers on 10G core
    switch-10G ===|2x10G LACP| tamale
    switch-10G ===|2x10G LACP| nacho
    switch-10G ---|2.5G| churro
    switch-10G ---|2.5G| mole

    %% Uplink to 2.5G access switch
    switch-2.5G ---|1G trunk| switch-10G

    %% Access layer devices
    switch-2.5G --- AP1
    switch-2.5G --- AP2
    switch-2.5G --- TV

    AP1 --- Office
    AP2 --- Lounge
```

### VLANs

Average amount of VLANs

| VLAN ID | Name    | Subnet         | Purpose                        | Typical devices / endpoints               |
|:--------|:--------|:---------------|:-------------------------------|:------------------------------------------|
| 10      | MGMT    | 10.10.10.0/24  | Infrastructure management      | Proxmox hosts, switches, APs, firewall    |
| 20      | SERVERS | 10.10.20.0/24  | K8s nodes and services         | compute-001/002/003 node IPs, VMs         |
| 30      | STORAGE | 10.10.30.0/24  | Ceph + NFS traffic             | compute-001/002/003, data-001             |
| 40      | LAN     | 10.10.40.0/24  | Trusted client network         | PCs, laptops, consoles, main Wi‑Fi SSID   |
| 50      | IOT     | 10.10.50.0/24  | IoT / smart devices            | IoT Wi‑Fi SSID, wired IoT, cameras        |
| 90      | GUEST   | 10.10.90.0/24  | Guest Wi‑Fi, internet‑only     | Guest SSID clients                        |

### IP Addresses

<https://docs.google.com/spreadsheets/d/1IyMLn-kNCPpK-noLq0pirywut8vm1mRgV0KqPe3ICpA/edit?usp=sharing>

## Talos cluster

A [Talos](https://www.talos.dev/) cluster is formed with VMs on the compute nodes.
Talos is a declarative, API-driven operating system specifically for Kubernetes.

Terraform (`./tf`) is used to manage the creation and configuration of the VMs.
This manages both the resources allocated to the VMs via Proxmox and the talos configuration.

```bash
cd tf
tofu apply
```

Environment variables (including `KUBECONFIG` and `TALOSCONFIG`) are auto-loaded via [direnv](https://direnv.net/) when entering the directory.

After applying, the `kubeconfig` and `talosconfig` files will be generated in `./tf/output`.
