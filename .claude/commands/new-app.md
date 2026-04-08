# New App

Scaffold a complete Kubernetes application deployment following this repository's
GitOps patterns: bjw-s app-template HelmRelease, per-app Flux Kustomization (`ks.yaml`),
Gateway API HTTPRoute with Authelia forward-auth, and VolSync backup.

## Input

$ARGUMENTS

If the user hasn't provided enough detail, gather the following before writing any files:

1. **App name** -- lowercase, hyphenated (e.g., `recyclarr`, `actual-budget`)
2. **Category** -- where it belongs: `media`, `apps`, `monitoring`, `core`, `security`, `storage`, `database`
3. **Image** -- container image repository and tag (e.g., `ghcr.io/home-operations/recyclarr:7.4.0`)
4. **Port** -- primary container port number
5. **Web route** -- does it need an HTTPRoute + Authelia middleware? (yes/no)
6. **Persistent storage** -- does it need a config PVC via rook-ceph-block? (yes/no, and size if yes)
7. **VolSync backup** -- does it need a ReplicationSource for config backup? (yes/no)
8. **Secrets** -- does it need SOPS-encrypted secrets? (yes/no)

## Step 1: Determine the app path

Based on category:

- `media` apps: `apps/production/apps/media/<app-name>/`
- `apps` category: `apps/production/apps/<app-name>/`
- Other categories: `apps/production/<category>/<app-name>/`

## Step 2: Create the app directory

Create these files in the app directory. Only include files the app actually needs.

### `kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
  # Include only what's needed:
  # - httproute.yaml         (if web route needed)
  # - <app>-secret.yaml      (if secrets needed)
  # - replicationsource.yaml (if volsync backup needed)
  # - namespace.yaml          (if app has its own namespace, not for media apps)
```

### `helmrelease.yaml`

Use the bjw-s app-template chart via the shared OCIRepository. Base this on the radarr
pattern at `apps/production/apps/media/radarr/helmrelease.yaml`.

Key conventions to follow:

- **Chart ref**: `OCIRepository/app-template` in `flux-system` namespace
- **Pod security**: `runAsUser/runAsGroup: 3000`, `runAsNonRoot: true`, `fsGroup: 3000`, `fsGroupChangePolicy: OnRootMismatch`
- **Container security**: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, drop ALL capabilities
- **Timezone**: always set `TZ: Australia/Melbourne`
- **YAML anchors**: use `&port` for the port number, `&probes` for liveness/readiness reuse
- **Health probes**: use the app's health endpoint (`/ping`, `/health`, or `/api/health`)
- **Resources**: start with `requests: {cpu: 10m, memory: 256Mi}`, `limits: {memory: 2Gi}`
- **Persistence**: config PVC via `rook-ceph-block` (typically 5Gi) at `/config`, `/tmp` as emptyDir
- **Media apps**: also mount `media-library` existing claim at `/data`

### `httproute.yaml` (if web route needed)

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app-name>
  namespace: <namespace>
spec:
  parentRefs:
    - name: home-gateway
      namespace: traefik
      sectionName: websecure
  hostnames:
    - <app-name>.home.lewelly.com
  rules:
    - filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: authelia-forwardauth
      backendRefs:
        - name: <app-name>
          port: <port>
```

For media apps, the `authelia-forwardauth` middleware already exists in the media namespace
(deployed via `media/shared/`). For apps in their own namespace, also create a `middleware.yaml`:

```yaml
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authelia-forwardauth
  namespace: <namespace>
spec:
  forwardAuth:
    address: http://authelia.authelia.svc.cluster.local:80/api/authz/forward-auth
    trustForwardHeader: true
    authResponseHeaders:
      - Remote-User
      - Remote-Groups
      - Remote-Email
      - Remote-Name
```

### `replicationsource.yaml` (if volsync backup needed)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: <app-name>
  namespace: <namespace>
spec:
  sourcePVC: <app-name>
  trigger:
    schedule: "0 16 * * *"
  kopia:
    accessModes:
      - ReadWriteOnce
    compression: zstd-fastest
    copyMethod: Snapshot
    moverSecurityContext:
      runAsUser: 3000
      runAsGroup: 3000
      fsGroup: 3000
    moverVolumes:
      - mountPath: repository
        volumeSource:
          nfs:
            path: /mnt/tank/backups/k8s
            server: 10.10.20.20
    parallelism: 2
    repository: volsync-secret
    retain:
      daily: 7
    storageClassName: rook-ceph-block
    volumeSnapshotClassName: csi-ceph-blockpool
```

### `namespace.yaml` (if app has its own namespace)

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <app-name>
```

Media apps share the `media` namespace and do not need this file.

## Step 3: Create the `ks.yaml` Flux Kustomization

Place `ks.yaml` in the app directory alongside `kustomization.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app-name>
  namespace: flux-system
spec:
  interval: 30m
  path: ./<path-to-app-directory>
  prune: true
  wait: true
  timeout: 5m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    # Set based on category:
    # media apps: [{name: media-shared}]
    # general apps: [{name: core}] + [{name: storage}] if PVC + [{name: security}] if auth
    # monitoring: [{name: core}]
  # Include only if app has SOPS-encrypted secrets:
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg
  postBuild:
    substitute:
      APP: <app-name>
```

## Step 4: Register in parent kustomization

Add the `ks.yaml` reference to the appropriate parent `kustomization.yaml`:

- **Media apps**: add `- <app-name>/ks.yaml` to `apps/production/apps/kustomization.yaml` under the media stack section
- **Other apps**: add `- <app-name>/ks.yaml` to the relevant category's parent kustomization

## Step 5: Validate

Run `make validate` to ensure all manifests are valid. Fix any issues before finishing.

## Category-specific notes

- **Media *arr apps** (radarr, sonarr, etc.): use `ghcr.io/home-operations/<app>` images, health probe at `/ping`, port varies per app
- **Media players** (jellyfin, plex): may need privileged security context for hardware transcoding
- **Monitoring exporters**: go in `apps/production/monitoring/`, depend on `core` only
- **Apps with databases**: add `dependsOn: [{name: database-clusters}]` to `ks.yaml`
- **Apps needing auth**: add `dependsOn: [{name: security}]` to `ks.yaml`
