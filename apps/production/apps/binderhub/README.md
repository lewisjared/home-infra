# JupyterHub for Climate-REF tutorials

Self-hosted [Zero-to-JupyterHub](https://z2jh.jupyter.org/) deployment that
spawns a prebuilt singleuser image with the
[`Climate-REF/climate-ref-tutorials`](https://github.com/Climate-REF/climate-ref-tutorials)
notebooks baked in.

> The directory is still named `binderhub/` for git-history continuity. The
> deployment was originally going to be BinderHub but on-cluster image builds
> (dind/repo2docker) don't work on Talos workers (`/var/lib/dind` is
> read-only ephemeral), so we switched to plain JupyterHub + a prebuilt image
> built out-of-cluster by CI in the tutorials repo.

- **Public URL**: <https://hub.climate-ref.org>
- **Auth**: none (DummyAuthenticator — any username, no password)
- **Singleuser image**: `ghcr.io/climate-ref/climate-ref-tutorials:latest`
- **TLS**: terminated at Cloudflare edge; origin is HTTP
- **Exposure**: home router 80/443 → traefik LoadBalancer → `home-gateway` web listener

## One-time out-of-band setup

1. **DNS**: add `hub.climate-ref.org` A record in Cloudflare pointing at the
   home WAN IP, **proxied** (orange cloud on).
2. **TLS mode** (Cloudflare → SSL/TLS): set to **Flexible** (CF terminates
   HTTPS, talks HTTP to origin).
3. **Router port-forward**: 80/443 → traefik LoadBalancer IP
   (`kubectl -n traefik get svc traefik` → EXTERNAL-IP).
4. **Generate `PROXY_TOKEN`** (`openssl rand -hex 32`) and encrypt
   `prereqs/secret.sops.yaml` (`sops --encrypt --in-place ...`).
5. **Build & push the singleuser image** to
   `ghcr.io/climate-ref/climate-ref-tutorials:latest` via CI in the tutorials
   repo. Image must be Jupyter-compatible
   (`jupyter/scipy-notebook`-style base; entrypoint runs
   `jupyterhub-singleuser`).

## Abuse mitigations

Layered controls — none alone is sufficient:

- **No code-build path** — only the prebuilt curated image can be spawned.
- **NetworkPolicy** on singleuser pods — internet egress allowed, all
  RFC1918 subnets blocked except DNS.
- **ResourceQuota** — namespace capped at 8 CPU / 32Gi memory / 30 pods.
- **LimitRange** — per-container default `1 CPU / 512Mi`, request
  `50m / 64Mi`.
- **Cull** — idle sessions killed after 10 min, hard-killed at 1h.
- **Cloudflare** — sits in front; flip on WAF / Cloudflare Access if abuse
  appears.

## Operating

```bash
flux reconcile kustomization binderhub
kubectl -n binderhub get pods
kubectl -n binderhub logs deploy/hub
kubectl -n binderhub logs deploy/proxy
kubectl -n binderhub get httproute jupyterhub -o yaml
```

## Known limitations

- Single replica for hub + proxy (no HA).
- DummyAuthenticator → no audit trail of who spawned what.
- DNS for `hub.climate-ref.org` is **not** managed by external-dns
  (scoped to `home.lewelly.com`); maintained manually in Cloudflare.
- No per-user storage; every session starts fresh from the image.
