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
