# JupyterHub for Climate-REF tutorials

Self-hosted [Zero-to-JupyterHub](https://z2jh.jupyter.org/) deployment that
spawns a prebuilt singleuser image with the
[`Climate-REF/climate-ref-tutorials`](https://github.com/Climate-REF/climate-ref-tutorials)
notebooks baked in.

> Directory is still named `binderhub/` for git-history continuity.
> Originally planned as BinderHub,
> but on-cluster image builds (dind/repo2docker) don't work on Talos workers
> (`/var/lib/dind` is read-only ephemeral),
> so we switched to plain JupyterHub with a prebuilt image built out-of-cluster by CI.

- **Public URL**: <https://hub.climate-ref.org>
- **Auth**: none (DummyAuthenticator — any username, no password)
- **Singleuser image**: `ghcr.io/climate-ref/climate-ref-tutorials:latest`
- **Exposure**: Cloudflare Tunnel.
  `cloudflared` runs in the `cloudflared` namespace (see `apps/production/core/cloudflared/`).
  CF Zero Trust dashboard maps `hub.climate-ref.org` → `http://proxy-public.binderhub.svc.cluster.local:80`.
  No public DNS A record, no router port-forward, no traefik gateway in the path.

## Abuse mitigations

Layered controls — none alone is sufficient:

- **No code-build path** — only the prebuilt curated image can be spawned.
- **NetworkPolicy** on singleuser pods — internet egress allowed,
  all RFC1918 subnets blocked except DNS.
- **ResourceQuota** — namespace capped at 8 CPU / 32Gi memory / 30 pods.
- **LimitRange** — per-container default `1 CPU / 512Mi`,
  request `50m / 64Mi`.
- **Cull** — idle sessions killed after 10 min, hard-killed at 1h.
- **Cloudflare** — sits in front;
  flip on WAF / Cloudflare Access if abuse appears.

## Operating

```bash
flux reconcile kustomization binderhub
kubectl -n binderhub get pods
kubectl -n binderhub logs deploy/hub
kubectl -n binderhub logs deploy/proxy
kubectl -n cloudflared logs deploy/cloudflared-climate-ref
```

Force a fresh singleuser image pull (next session starts with the new digest):

```bash
kubectl -n binderhub delete pod -l component=singleuser-server
```

## Known limitations

- Single replica for hub + proxy (no HA).
- DummyAuthenticator → no audit trail of who spawned what.
- DNS for `hub.climate-ref.org` is managed in CF dashboard (tunnel CNAME),
  not by external-dns (which is scoped to `home.lewelly.com`).
- No per-user storage; every session starts fresh from the image.
