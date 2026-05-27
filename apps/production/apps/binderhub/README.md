# BinderHub

Self-hosted [BinderHub](https://binderhub.readthedocs.io/) restricted to a
single repository: [`Climate-REF/climate-ref-tutorials`](https://github.com/Climate-REF/climate-ref-tutorials).

- **Public URL**: <https://binder.climate-ref.org>
- **Auth**: none (public)
- **Image registry**: in-cluster (`registry.binderhub.svc.cluster.local:5000`)
- **TLS**: terminated at Cloudflare edge; origin is HTTP
- **Exposure**: home router 80/443 → traefik LoadBalancer → `home-gateway` web listener

## One-time out-of-band setup

This is required before the service is reachable:

1. **DNS**: add `binder.climate-ref.org` A record in Cloudflare pointing at the home WAN IP, **proxied** (orange cloud on).
2. **TLS mode** (Cloudflare → SSL/TLS): set to **Flexible** (CF terminates HTTPS, talks HTTP to origin). Or use **Full** if you
   later add an origin certificate.
3. **Router port-forward**: forward 80/443 → traefik LoadBalancer IP
   (`kubectl -n traefik get svc traefik` → EXTERNAL-IP).
4. **Generate secrets** (openssl rand -hex 32) and encrypt apps/production/apps/binderhub/secret.sops.yaml

## Repo whitelist

Hard-coded in `helmrelease.yaml`:

```yaml
config:
  GitHubRepoProvider:
    allowed_specs:
      - "^Climate-REF/climate-ref-tutorials/.*$"
    banned_specs:
      - "^(?!Climate-REF/climate-ref-tutorials/).*$"
```

Any URL like `/v2/gh/<other-org>/<other-repo>/...` is rejected by
BinderHub before any build/spawn occurs.

## Abuse mitigations

Layered controls — none alone is sufficient:

- **Repo whitelist** (see above) — only one repo can be built.
- **NetworkPolicy** on single-user pods — internet egress allowed but all
  RFC1918 subnets are blocked except DNS.
- **ResourceQuota** — namespace capped at 8 CPU / 32Gi memory / 30 pods.
- **Cull** — idle sessions killed after 10 min, hard-killed at 1h.
- **Cloudflare** — sits in front; can flip on WAF rules / Cloudflare Access
  for additional gating if abuse appears.

## Operating

```bash
flux reconcile kustomization binderhub
kubectl -n binderhub get pods
kubectl -n binderhub logs deploy/binder
kubectl -n binderhub logs deploy/hub
kubectl -n binderhub get httproute binderhub -o yaml

# Manual GC (instead of waiting for weekly CronJob)
kubectl -n binderhub create job --from=cronjob/registry-gc registry-gc-manual
```

## Known limitations

- Single replica for hub, proxy, registry (no HA).
- Built images live on a RWO `rook-ceph-block` PVC; node failure during
  reconcile may briefly stall the registry pod.
- No metrics scrape configured yet — add a ServiceMonitor under
  `apps/production/monitoring/` if usage justifies it.
- DNS for `binder.climate-ref.org` is **not** managed by external-dns
  (which is scoped to `home.lewelly.com`); it is maintained manually in
  Cloudflare.
