# Security tooling options: intrusion detection and compliance

Status: investigation, nothing here is deployed yet.
Scope: the Talos cluster, with the Climate-REF workloads as the test case
(`apps/production/apps/climate-ref/` and the Climate-REF runners in `apps/production/apps/github-runners/runners-ref/`).

## Why Climate-REF is the right test case

Climate-REF runs code the cluster owner did not write:

- The **Climate-REF org runners** (`runners-ref`, 0 to 6 pods) run pull request code from a public GitHub org.
  The existing controls are good: no service account token, ingress denied, egress limited to DNS, the Actions cache
  and the public internet with private ranges carved out.
  But nothing **detects** abuse such as crypto-mining, scanning out to the internet or container-escape attempts.
  They share the `github-runners` namespace, which is PSA `privileged` for the dind runners of other repos, and they
  mount the CMIP6 NFS share.
- `climate-ref.home.lewelly.com` and Flower sit behind Authelia, which is good, but the `climate-ref` namespace has no
  Pod Security labels or NetworkPolicies, so it falls back to the Talos cluster defaults.
- The `esgf-fetch` cronjob pulls data from external ESGF nodes onto shared NFS.

BinderHub (`hub.climate-ref.org`, a public no-auth JupyterHub) was disabled on 2026-06-14 by commenting it out of
`apps/production/apps/kustomization.yaml`.
That Flux Kustomization has `prune: false`, so commenting it out stops Flux reconciling BinderHub but does not delete
it. Confirm it is gone:

```bash
kubectl get kustomization -n flux-system binderhub
kubectl get ns binderhub
```

The `cloudflared-climate-ref` tunnel still runs with 2 replicas.
Remove the `hub.climate-ref.org` public hostname in the Cloudflare Zero Trust dashboard too, or scale the tunnel to
zero if nothing else uses it.

## What already exists

| Control                | Where                                         | Gap                                                  |
| ---------------------- | --------------------------------------------- | ---------------------------------------------------- |
| SSO + TOTP             | Authelia (`security/`)                        | -                                                    |
| Secrets encryption     | SOPS/PGP, Flux decrypts                       | -                                                    |
| Pod Security Admission | Labels on some namespaces                     | Missing on `climate-ref` and most apps; no reporting |
| Network policy         | Cilium, a few namespaces                      | No default-deny; no flow retention                   |
| Network visibility     | Hubble relay + UI                             | Flows are live only, nothing is stored or alerted on |
| Logs                   | Alloy -> Loki (pod logs, cluster events)      | kube-apiserver audit log is not collected            |
| Metrics + alerting     | Prometheus, Alertmanager, `components/alerts` | No security alerts                                   |
| Image updates          | Renovate, pinned digests for app-template     | No vulnerability scanning, no signature verification |
| Immutable OS           | Talos (no SSH, read-only rootfs, API only)    | Strong baseline; Proxmox hosts are ordinary Debian   |
| Backups                | Volsync, CNPG barman                          | -                                                    |

## The capabilities compliance frameworks expect

Whichever framework applies (ISO 27001 Annex A, NIST CSF / 800-53, CIS Controls, ASD Essential Eight, or a funder's
security questionnaire), the asks for a hosted research service reduce to roughly the same list:

1. **Audit logging**: who did what to the cluster, kept for a defined period (typically 90 days to 1 year).
2. **Runtime intrusion detection**: alert on suspicious behaviour in workloads and on nodes.
3. **Vulnerability management**: scan images and track findings.
4. **Configuration / benchmark compliance**: evidence against CIS, NSA/CISA or Pod Security Standards.
5. **Policy enforcement**: stop non-compliant workloads at admission.
6. **Network monitoring and segmentation**: default-deny and retained flow logs.
7. **Host integrity**: file-integrity monitoring on the hosts that are not immutable.
8. **Alerting and evidence**: findings routed somewhere a human sees, and reports that can be handed to an auditor.

The options for each follow. Recommendations are marked **(rec)**.

## 1. Kubernetes audit logging

Talos enables kube-apiserver auditing by default: a built-in Metadata-level policy writes to
`/var/log/audit/kube/kube-apiserver.log` on each control-plane node.
The policy is configurable with `cluster.apiServer.auditPolicy` in the machine config
(`tf/modules/talos-cluster/config.tf`, `controlplane_patches`).
Today those files rotate on the node and are never shipped.

| Option                                         | Notes                                                                                                                                                                                                        |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Alloy tails the audit file into Loki (rec)** | Add a `hostPath` mount of `/var/log/audit/kube` on control-plane nodes to the existing k8s-monitoring Alloy config. No new component. Retention is Loki's.                                                   |
| Audit webhook to Falco `k8saudit` plugin       | Real-time rule evaluation on API events, but needs `audit-webhook-config-file` wired through Talos `extraArgs` and an extra volume. More moving parts.                                                       |
| Talos `machine.logging.destinations`           | Ships Talos service logs (apid, machined, kubelet) as JSON over TCP/UDP. Worth adding to Alloy as a receiver at the same time: Talos has no journald, so Alloy's `nodeLogs` collects little or nothing here. |

Tighten the audit policy to log `RequestResponse` for Secrets, RBAC, `pods/exec`, `pods/attach` and
`pods/portforward`, and `Metadata` for the rest.

## 2. Runtime intrusion detection

This is the core of the request. All three candidates are eBPF-based, so they work on Talos, which refuses kernel
modules.

| Tool              | Strengths                                                                                                                                                                                                                                                                                                                 | Weaknesses                                                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Falco (rec)**   | CNCF graduated. Large maintained rule set (shells in containers, crypto-miners, sensitive file reads, privilege escalation, outbound to unusual ports) with MITRE ATT&CK and PCI/NIST tags. `modern_ebpf` driver needs nothing from the host. Falcosidekick fans out to Loki, Alertmanager, Slack and others. Helm chart. | Detection only. Rule tuning is needed: CI runner pods spawn shells by design, so the "terminal shell in container" rule must be scoped. |
| Tetragon          | From the Cilium project and fits the existing Cilium install. Can **enforce** (SIGKILL a process, override a syscall) not just detect. Very low overhead. Process, file and network events with pod identity.                                                                                                             | Ships with almost no default policies: you write `TracingPolicy` CRDs yourself. Less compliance mapping out of the box.                 |
| KubeArmor         | LSM-based enforcement (AppArmor/BPF-LSM) with per-workload policies.                                                                                                                                                                                                                                                      | Talos has no AppArmor. BPF-LSM needs `lsm=...,bpf` on the kernel cmdline. Smaller community.                                            |
| Kubescape runtime | Part of Kubescape (see section 4), learns per-workload baselines and flags anomalies.                                                                                                                                                                                                                                     | Younger than Falco; heavier when every feature is on.                                                                                   |

Recommendation: **Falco now, Tetragon later for enforcement on the untrusted runners.**
Falco gives immediate, auditable detection with a rule library an assessor will recognise.
Once the runner baseline is known, a Tetragon `TracingPolicy` that kills known miner binaries or blocks
`ptrace`/`mount` in `network-policy: untrusted-runner` pods is a good second step.

Falco rules to enable or write for Climate-REF:

- Crypto-mining: miner binaries and connections to mining pools (stratum ports 3333, 4444, 5555, 7777, 14444).
- Writes to the CMIP6 mount or outside the work and cache directories in runner pods.
- Reads of `/proc/*/environ` or other pods' files from runner pods.
- Outbound connections from `climate-ref` pods to anything other than ESGF and package mirrors.
- Unexpected processes in the API and worker images (anything that is not `python`, `celery` or `ref`).

## 3. Vulnerability scanning

| Option                   | Notes                                                                                                                                                                                                                                                           |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Trivy Operator (rec)** | Scans every running image and stores `VulnerabilityReport` CRDs. Also produces `ConfigAuditReport`, `ExposedSecretReport`, `RbacAssessmentReport` and `ClusterComplianceReport` (see section 4). Exports Prometheus metrics, so alerts fit `components/alerts`. |
| Kubescape                | Also scans images, alongside its posture checks.                                                                                                                                                                                                                |
| Trivy in CI              | Scan upstream images on Renovate PRs. Cheap, but only covers what goes through the repo; images that jobs pull at runtime bypass it.                                                                                                                            |

## 4. Configuration and benchmark compliance

| Option                              | Frameworks                                                     | Notes                                                                                                                    |
| ----------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Trivy Operator compliance (rec)** | `k8s-cis`, `k8s-nsa`, `k8s-pss-baseline`, `k8s-pss-restricted` | Same component as section 3. Reports are CRDs, so `kubectl get clustercompliancereport -o yaml` is the auditor evidence. |
| Kubescape                           | NSA/CISA, MITRE ATT&CK, CIS, SOC 2, ArmoBest                   | Broader framework list and a nicer UI. A second operator if Trivy is also deployed.                                      |
| kube-bench                          | CIS                                                            | Expects files and flags at kubeadm paths; on Talos most checks report wrong or N/A. Not recommended.                     |

Note that a CIS benchmark run on Talos produces false failures because Talos lays things out differently.
Keep a short exceptions file that maps each one to the Talos control that covers it (for example, no SSH, immutable
rootfs, API mTLS).

## 5. Admission policy

| Option                             | Notes                                                                                                                                                                                                                                                                                  |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pod Security Admission labels only | Already used. Free. Give every namespace an explicit `enforce` label and set `audit`/`warn` to `restricted` where possible.                                                                                                                                                            |
| **Kyverno (rec)**                  | Policies are plain YAML, which suits this repo. Has a PSS policy library, `PolicyReport` CRDs for evidence, image signature verification (cosign), and mutation (for example, inject `automountServiceAccountToken: false` into untrusted runner pods). Can run in `Audit` mode first. |
| OPA Gatekeeper                     | Rego. More powerful, more to maintain. Not worth it at this scale.                                                                                                                                                                                                                     |
| `ValidatingAdmissionPolicy` (CEL)  | Built into Kubernetes, no controller. Fine for a handful of rules; no reports.                                                                                                                                                                                                         |

Kyverno policies to start with: require PSA labels on namespaces, disallow `:latest`, require resource limits,
restrict `hostPath`, require registries from an allow-list, and allow `privileged` in `github-runners` only for the
dind sidecar.
Moving the Climate-REF runners to their own `baseline` namespace would do the last one without Kyverno.

## 6. Network monitoring and segmentation

- **Hubble flow export (rec)**: enable `hubble.export` in `tf/manifests/cilium/cilium-values.yaml` with a filter for
  dropped flows and flows from `github-runners` and `climate-ref`, and let Alloy ship them to Loki.
  This gives retained network evidence at no new component cost.
- **Default-deny CiliumNetworkPolicy** per namespace, starting with `climate-ref`: allow ingress from Traefik, egress to
  DNS, Dragonfly, Prometheus (KEDA) and ESGF.
- **CrowdSec + Traefik bouncer**: behaviour-based blocking of brute force and scanning at the ingress.
  Lower value here because public traffic already comes through Cloudflare, and Cloudflare WAF and rate-limit rules
  are the cheaper first step.
- **Suricata/Zeek on the router (`taco`)**: classic network IDS for north-south traffic.
  Worth it once the VLAN migration is done; it sees nothing east-west inside the cluster, which Hubble covers.

## 7. Host integrity (Proxmox)

Talos nodes are immutable and have no shell, so host IDS agents do not apply there.
The five Proxmox hosts are ordinary Debian and are the most valuable target (they hold every VM disk).

| Option                                    | Notes                                                                                                                                                                                                                |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wazuh                                     | Full SIEM/XDR: agent-based FIM, rootkit checks, SCA (CIS Debian), vulnerability detection and PCI/NIST/GDPR mappings. Heavy: the indexer wants several GB of RAM. Best if a single compliance dashboard is required. |
| **auditd + AIDE, shipped by Alloy (rec)** | Light and managed from the existing `ansible/` playbooks. FIM and syscall audit land in the same Loki as everything else.                                                                                            |
| Falco on Proxmox hosts                    | Falco also runs as a host service, so the same rule language covers the hosts.                                                                                                                                       |

## 8. Alerting and evidence

- Route Falco (via Falcosidekick), Trivy Operator metrics and Kyverno policy violations to the existing Alertmanager,
  so security alerts follow the same path as the rest of `ALERTING.md`.
- Add a Grafana "Security" dashboard: Falco events by rule and namespace, open critical CVEs, policy violations,
  dropped flows.
- Set Loki retention for security streams to the period the framework requires, and back it up with the existing
  Volsync/S3 path.

## Recommended rollout

Ordered by value for effort. Each step is a new component under `apps/production/security/` (and a repo in
`helmfile.yaml`), except where noted.

| Step | Change                                                                                                       | Effort | Covers |
| ---- | ------------------------------------------------------------------------------------------------------------ | ------ | ------ |
| 1    | Ship kube-apiserver audit logs and Talos service logs to Loki (Alloy, Talos patch)                           | S      | 1, 8   |
| 2    | Falco + Falcosidekick, with Climate-REF and runner rules, alerts to Alertmanager                             | M      | 2, 8   |
| 3    | Trivy Operator with the `k8s-pss-baseline` and `k8s-nsa` compliance reports                                  | S      | 3, 4   |
| 4    | PSA labels on every namespace; default-deny CiliumNetworkPolicy for `climate-ref`; confirm BinderHub is gone | S      | 5, 6   |
| 5    | Kyverno in `Audit` mode, then `Enforce`                                                                      | M      | 5, 4   |
| 6    | Hubble flow export to Loki                                                                                   | S      | 6      |
| 7    | auditd + AIDE on Proxmox hosts via Ansible                                                                   | M      | 7      |
| 8    | Tetragon enforcement policies for untrusted runner pods                                                      | M      | 2      |

Steps 1 to 4 give a defensible position for most questionnaires: audit trail, intrusion detection, vulnerability
management and a benchmark report.

Resource cost on this cluster is modest: Falco and Tetragon are about 100-200 MiB per node each, Trivy Operator and
Kyverno a few hundred MiB in total.
Wazuh is the only option that needs real capacity planning.

## Open questions

- Which framework or questionnaire is this for (for example, an institutional ISO 27001 review, NIST 800-171, a funder
  requirement)? That decides log retention and whether Wazuh's dashboards are worth their weight.
- Do the Climate-REF org workflows require approval before running on fork pull requests? That GitHub setting is the
  main control on who can run code on the runners, and auditors will ask about it.
- If BinderHub comes back, it needs GitHub or ORCID login rather than no auth, so every session is attributable.
- Where should alerts go out of hours (email, Slack, phone push)?
