# agentbox

Shared parts for long-running agent instances: the namespace, the `agentbox` ServiceAccount
with read-only `view` access to the cluster, and ingress limited to ssh from private ranges.

The instances themselves are created and destroyed by the
[herdr-agentbox](https://github.com/lewisjared/herdr-agentbox) plugin, outside Flux.
Each gets a LoadBalancer IP from `home-pool` and the name `<name>.agents.home.lewelly.com`.

The `agentbox-claude-credentials` Secret is pushed by the plugin's credentials action, not stored in Git,
because the Claude login rotates.

Egress is unrestricted for now.
