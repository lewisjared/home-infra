# OIDC Integration Quick Reference

Quick reference for integrating applications with Authelia OIDC.

## Authelia OIDC Endpoints

| Endpoint      | URL                                                              |
| ------------- | ---------------------------------------------------------------- |
| Issuer        | `https://auth.home.lewelly.com`                                  |
| Discovery     | `https://auth.home.lewelly.com/.well-known/openid-configuration` |
| Authorization | `https://auth.home.lewelly.com/api/oidc/authorization`           |
| Token         | `https://auth.home.lewelly.com/api/oidc/token`                   |
| UserInfo      | `https://auth.home.lewelly.com/api/oidc/userinfo`                |
| JWKS          | `https://auth.home.lewelly.com/jwks.json`                        |

## Configured Clients

| Application | Client ID    | Callback URL                                                    |
| ----------- | ------------ | --------------------------------------------------------------- |
| Grafana     | `grafana`    | `https://grafana.home.lewelly.com/login/generic_oauth`          |
| Headlamp    | `headlamp`   | `https://headlamp.home.lewelly.com/oidc-callback`               |
| Jellyfin    | `jellyfin`   | `https://jellyfin.home.lewelly.com/sso/OID/redirect/authelia`   |
| Jellyseerr  | `jellyseerr` | `https://jellyseerr.home.lewelly.com/api/v1/auth/oidc-callback` |

## Adding a New OIDC Client

### 1. Generate client secret and hash

```bash
# Generate random secret
SECRET=$(openssl rand -hex 32)
echo "Plain secret: $SECRET"

# Generate PBKDF2 hash for Authelia config
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate pbkdf2 --password "$SECRET"
```

### 2. Add client to Authelia

Edit `apps/production/security/authelia/authelia.yaml`:

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: app-name
        client_name: Application Name
        client_secret: "$pbkdf2-sha512$310000$..."  # Hash from step 1
        public: false
        authorization_policy: one_factor
        redirect_uris:
          - https://app.home.lewelly.com/callback
        scopes:
          - openid
          - profile
          - email
          - groups
        grant_types:
          - authorization_code
        response_types:
          - code
        userinfo_signed_response_alg: none
        token_endpoint_auth_method: client_secret_basic
```

### 3. Validate and deploy

```bash
make validate
git add apps/production/security/authelia/
git commit -m "feat(authelia): add OIDC client for app-name"
git push
```

## In-Cluster URL Configuration

When configuring OIDC for Kubernetes-hosted applications:

| URL Type    | Use Case         | URL Pattern                                                    |
| ----------- | ---------------- | -------------------------------------------------------------- |
| `auth_url`  | Browser redirect | `https://auth.home.lewelly.com/api/oidc/authorization`         |
| `token_url` | Server-side call | `http://authelia.authelia.svc.cluster.local/api/oidc/token`    |
| `api_url`   | Server-side call | `http://authelia.authelia.svc.cluster.local/api/oidc/userinfo` |

Browser-side URLs must use external HTTPS. Server-side URLs should use the internal Kubernetes service for reliability.

## Troubleshooting

### Check Authelia logs

```bash
kubectl logs -n authelia -l app.kubernetes.io/name=authelia -f --tail=100
```

### Test OIDC discovery

```bash
curl -s https://auth.home.lewelly.com/.well-known/openid-configuration | jq
```

### Common errors

| Error                        | Solution                                      |
| ---------------------------- | --------------------------------------------- |
| `invalid redirect_uri`       | Verify redirect_uris match exactly in config  |
| `invalid client credentials` | Check client_secret hash matches plain secret |
| `access forbidden`           | Verify access_control rules allow the domain  |

## File Locations

```raw
apps/production/security/authelia/
├── authelia.yaml           # OIDC client configuration
└── authelia-secrets.yaml   # SOPS-encrypted secrets (JWKS key)

apps/production/monitoring/prometheus/
├── kube-prometheus-stack.yaml  # Grafana OIDC config
└── grafana-oidc-secret.yaml    # Grafana client secret
```

## References

- [Authelia OIDC Client Examples](https://www.authelia.com/integration/openid-connect/clients/) - App-specific configuration guides
