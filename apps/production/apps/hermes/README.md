# Hermes deployment notes

This deployment is the current privileged diagnostics instance:
it runs with a cluster-wide read-only diagnostic ServiceAccount, debug subresource access
(`pods/exec`, `pods/attach`, `pods/portforward`), and private URL access enabled for in-cluster troubleshooting.

Hermes profiles and chat allowlists are useful administration tools, but they are not a hard security boundary.
If normal chat usage should be separated from cluster diagnostics,
create a second Hermes deployment rather than only adding a second profile inside this pod.

Recommended split path:

1. Keep this instance as `hermes-admin`/diagnostics with restricted admin-only
   chat channels, the diagnostic RBAC, and private URL access.
2. Add a separate non-privileged `hermes` instance with its own namespace or
   labels, ServiceAccount, Secret, PVC, NetworkPolicy, and bot identity/channel.
3. Give the normal instance no Kubernetes API RBAC, keep
   `HERMES_ALLOW_PRIVATE_URLS` disabled, and add egress policy excluding RFC1918/cluster destinations.
4. Route day-to-day chat to the non-privileged instance;
   use the privileged instance only for trusted cluster administration.

## Model provider: ChatGPT subscription

Hermes uses the `openai-codex` provider, which bills against the ChatGPT plan rather than per API token.
Credentials live in `/opt/data/auth.json` on the PVC, so they survive restarts and are backed up by VolSync.

Log in with the device-code flow, then select the provider and model:

```bash
kubectl -n hermes exec -it deploy/hermes -c main -- hermes auth add openai-codex
kubectl -n hermes exec -it deploy/hermes -c main -- hermes model
```

Re-run `hermes auth add openai-codex` if the logs report a dead refresh token.

## Webapp

The gateway serves the Webapp at <https://hermes.home.lewelly.com>, signed in through Authelia.
Its settings are pinned in `managed-config.yaml` (Hermes managed scope), so `hermes config set webapp.*` in the pod has no effect.
