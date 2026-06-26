# OpenViking

OpenViking is deployed as an internal context database for Hermes and other agents.

Access:

- In-cluster API: `http://openviking.openviking.svc.cluster.local:1933`
- Internal Web Studio: `https://openviking.home.lewelly.com/studio`
- Health endpoint: `/health`
- Readiness endpoint: `/ready`

The app uses a single RWO PVC for the local OpenViking workspace/RocksDB state.
Rollouts use `Recreate` to avoid two pods touching the same database.

Current config enables local storage, a generated PVC-persisted root API key,
and Ollama-backed text embeddings via the shared in-cluster Ollama service. The
external route is protected with Authelia; if exposing the API beyond trusted
internal clients, replace the runtime-generated root key with a SOPS-backed
managed secret.

Hermes can be pointed at the service with:

```bash
hermes memory setup
# select openviking
# endpoint: http://openviking.openviking.svc.cluster.local:1933
```
