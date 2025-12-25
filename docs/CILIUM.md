# Cilium CNI

Cilium is the Container Network Interface (CNI) plugin for the Kubernetes cluster, providing eBPF-based networking, security, and observability.

## Architecture

Cilium is deployed as an **inline manifest** during Talos cluster bootstrap, before any other workloads.
This is required because the CNI must be available for pods to have networking.

```raw
tf/manifests/cilium/
├── cilium-values.yaml      # Helm values for configuration
└── cilium-install.yaml     # Pre-rendered Helm template (applied at bootstrap)
```

The manifest is loaded by Terraform and embedded in the Talos machine configuration:

```hcl
# tf/modules/talos-cluster/config.tf
cluster = {
  inlineManifests = [
    {
      name     = "cilium"
      contents = local.cilium_manifest
    }
  ]
}
```

## Key Configuration

### Hubble Observability

Hubble provides network observability (flow logs, metrics, UI). TLS is managed via the `cronJob` method:

```yaml
hubble:
  enabled: true
  tls:
    auto:
      method: cronJob # CA created in-cluster, persists across upgrades
  relay:
    enabled: true
  ui:
    enabled: true
```

**Why cronJob?** The `cronJob` method creates the CA certificate once in the cluster and renews leaf certificates automatically. This avoids:

- Storing secrets in git
- Breaking mTLS on upgrades (helm method regenerates CA each time)
- Manual certificate management

### Other Features

- **kubeProxyReplacement**: Cilium replaces kube-proxy with eBPF
- **L2 Announcements**: Enabled for LoadBalancer services
- **Gateway API**: Enabled for ingress/gateway routing

## Upgrading Cilium

### Prerequisites

- `helm` CLI installed
- Cilium Helm repo configured: `helm repo add cilium https://helm.cilium.io/`
- Update the repo: `helm repo update`

### Upgrade Process

1. **Check available versions**:

   ```bash
   helm search repo cilium/cilium -l | head -10
   ```

2. **Review release notes** for breaking changes:
   - <https://docs.cilium.io/en/stable/operations/upgrade/>

3. **Update values if needed** in `tf/manifests/cilium/cilium-values.yaml`

4. **Regenerate the manifest**:

   ```bash
   helm template cilium cilium/cilium \
     --version <NEW_VERSION> \
     --namespace kube-system \
     -f tf/manifests/cilium/cilium-values.yaml \
     > tf/manifests/cilium/cilium-install.yaml
   ```

5. **Validate the manifest**:

   ```bash
   make validate
   ```

6. **Review changes**:

   ```bash
   git diff tf/manifests/cilium/cilium-install.yaml
   ```

7. **Commit and push**:

   ```bash
   git add tf/manifests/cilium/
   git commit -m "chore: upgrade cilium to <VERSION>"
   git push
   ```

8. **Apply to running cluster** (if cluster already exists):

   ```bash
   kubectl apply -f tf/manifests/cilium/cilium-install.yaml
   ```

   For new clusters, Terraform will apply the manifest during bootstrap.

### Post-Upgrade Verification

```bash
# Check Cilium pods are running
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium status
kubectl exec -n kube-system -l k8s-app=cilium -- cilium status

# Verify Hubble is working
kubectl get pods -n kube-system -l k8s-app=hubble-relay
kubectl get pods -n kube-system -l k8s-app=hubble-ui

# Check certificate generation job ran successfully
kubectl get jobs -n kube-system -l k8s-app=hubble-generate-certs
```

## Changing Configuration

To modify Cilium configuration:

1. Edit `tf/manifests/cilium/cilium-values.yaml`
2. Regenerate the manifest (same as upgrade process, use current version)
3. Apply changes

**Common configuration changes**:

- Enable/disable features in values file
- Adjust resource limits
- Configure network policies

## TLS Certificate Management

Hubble uses mTLS for secure communication between components. With `cronJob` method:

- **Initial Setup**: A Job creates the CA and leaf certificates on first boot
- **Rotation**: A CronJob renews certificates before expiry
- **Persistence**: CA secret (`cilium-ca`) persists in the cluster

Certificates are stored as Kubernetes secrets:

- `cilium-ca` - Root CA (created once, never regenerated)
- `hubble-server-certs` - Hubble server TLS
- `hubble-relay-client-certs` - Relay client TLS

## Troubleshooting

### Cilium Pods Not Starting

```bash
# Check pod status and events
kubectl describe pods -n kube-system -l k8s-app=cilium

# Check logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100
```

### Hubble Not Working

```bash
# Check relay logs
kubectl logs -n kube-system -l k8s-app=hubble-relay

# Check if certs were generated
kubectl get secrets -n kube-system | grep hubble

# Check cert generation job
kubectl logs -n kube-system -l k8s-app=hubble-generate-certs
```

### Network Connectivity Issues

```bash
# Run Cilium connectivity test
kubectl exec -n kube-system -l k8s-app=cilium -- cilium connectivity test

# Check BPF maps
kubectl exec -n kube-system -l k8s-app=cilium -- cilium bpf endpoint list
```

## Hubble UI Access

Hubble UI is exposed via Gateway API HTTPRoute at:

```raw
https://hubble.home.lewelly.com
```

The HTTPRoute is defined in `infrastructure/base/hubble-ui/httproute.yaml` and routes to the `hubble-ui` service in `kube-system` namespace.

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [Cilium on Talos](https://www.talos.dev/v1.9/kubernetes-guides/network/deploying-cilium/)
- [Hubble Documentation](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Cilium Helm Values Reference](https://docs.cilium.io/en/stable/helm-reference/)
