# OpenViking

OpenViking is deployed as an internal context database for Hermes and other agents.

Access:

- In-cluster API: `http://openviking.openviking.svc.cluster.local:1933`
- Internal Web Studio: `https://openviking.home.lewelly.com/studio`
- Health endpoint: `/health`
- Readiness endpoint: `/ready`

The app uses a single RWO PVC for the local OpenViking workspace/RocksDB state.
Rollouts use `Recreate` to avoid two pods touching the same database.

Current config enables local storage, a SOPS-managed root API key (`openviking-secret`),
and Ollama-backed text embeddings via the shared in-cluster Ollama service.

## Auth

The OpenViking server enforces `auth_mode: api_key` for the API, `/mcp` and Studio.

The root key lives in `openviking-secret.yaml` (SOPS/PGP, `stringData` encrypted in place).
 To rotate:

```bash
key=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)
yq -i ".stringData.OPENVIKING_ROOT_API_KEY = \"$key\"" openviking-secret.yaml
sops --encrypt --in-place openviking-secret.yaml
```

Reloader restarts the pod (`Recreate`) on secret change. Keep the key
constrained to `[A-Za-z0-9]` so it stays sed-safe when rendered into `ov.conf`.

## Clients

Hermes (in-cluster) can be pointed at the service with:

```bash
hermes memory setup
# select openviking
# endpoint: http://openviking.openviking.svc.cluster.local:1933
```

A laptop MCP client (over Tailscale) uses the route plus the api key, e.g.:

```bash
claude mcp add --transport http openviking https://openviking.home.lewelly.com/mcp \
  --header "Authorization: Bearer $OPENVIKING_API_KEY"
```
