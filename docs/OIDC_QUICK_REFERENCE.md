# OIDC Integration Quick Reference

Quick reference for integrating applications with Authelia OIDC.

## Authelia OIDC Endpoints

```raw
Issuer:        https://auth.home.lewelly.com
Discovery:     https://auth.home.lewelly.com/.well-known/openid-configuration
Authorization: https://auth.home.lewelly.com/api/oidc/authorization
Token:         https://auth.home.lewelly.com/api/oidc/token
UserInfo:      https://auth.home.lewelly.com/api/oidc/userinfo
JWKS:          https://auth.home.lewelly.com/jwks.json
```

## Standard Configuration Template

### Authelia Client Configuration

```yaml
# infrastructure/authelia/authelia.yaml
configMap:
  identity_providers:
    oidc:
      clients:
        - client_id: app-name
          client_name: Application Display Name
          client_secret:
            path: app-name-client-secret
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
          response_modes:
            - form_post
            - query
          userinfo_signed_response_alg: none

  access_control:
    rules:
      - domain: app.home.lewelly.com
        policy: one_factor
```

### Generate Secret

```bash
openssl rand -base64 32
```

### Add to Authelia Secrets

```bash
sops infrastructure/authelia/authelia-secrets.yaml
```

```yaml
stringData:
  app-name-client-secret: YOUR_GENERATED_SECRET
```

## Common Callback URLs

| Application | Callback URL Pattern                              |
| ----------- | ------------------------------------------------- |
| Grafana     | `https://HOST/login/generic_oauth`                |
| Harbor      | `https://HOST/c/oidc/callback`                    |
| Nextcloud   | `https://HOST/apps/user_oidc/code`                |
| Portainer   | `https://HOST/`                                   |
| GitLab      | `https://HOST/users/auth/openid_connect/callback` |
| Vault       | `https://HOST/ui/vault/auth/oidc/oidc/callback`   |
| Proxmox     | `https://HOST/api2/oidc/callback`                 |
| Wekan       | `https://HOST/_oauth/oidc`                        |
| Mattermost  | `https://HOST/signup/oidc/complete`               |

## Application-Specific Configurations

### Grafana

**Callback**: `https://grafana.home.lewelly.com/login/generic_oauth`

```yaml
# In kube-prometheus-stack values
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.home.lewelly.com
    auth.generic_oauth:
      enabled: true
      name: Authelia
      client_id: grafana
      client_secret: ${GRAFANA_OIDC_CLIENT_SECRET}
      scopes: openid profile email groups
      auth_url: https://auth.home.lewelly.com/api/oidc/authorization
      token_url: https://auth.home.lewelly.com/api/oidc/token
      api_url: https://auth.home.lewelly.com/api/oidc/userinfo
      login_attribute_path: preferred_username
      groups_attribute_path: groups
      name_attribute_path: name
      email_attribute_path: email
      role_attribute_path: contains(groups[*], 'admins') && 'Admin' || 'Viewer'
      allow_sign_up: true
```

---

### Harbor

**Callback**: `https://harbor.home.lewelly.com/c/oidc/callback`

```yaml
# Via Harbor UI: Administration → Configuration → Authentication
Auth Mode: OIDC
OIDC Provider Name: authelia
OIDC Endpoint: https://auth.home.lewelly.com
OIDC Client ID: harbor
OIDC Client Secret: <secret>
OIDC Groups Claim: groups
OIDC Scope: openid,profile,email,groups
Verify Certificate: Yes
Automatic onboarding: Yes
Username Claim: preferred_username
```

---

### Nextcloud

**Callback**: `https://nextcloud.home.lewelly.com/apps/user_oidc/code`

First install `user_oidc` app, then:

```bash
# Via occ command
occ config:app:set user_oidc provider-1-clientId --value='nextcloud'
occ config:app:set user_oidc provider-1-clientSecret --value='<secret>'
occ config:app:set user_oidc provider-1-discoveryUri --value='https://auth.home.lewelly.com/.well-known/openid-configuration'
occ config:app:set user_oidc provider-1-scope --value='openid profile email groups'
```

---

### Portainer

**Callback**: `https://portainer.home.lewelly.com/`

```bash
# Via Portainer UI: Settings → Authentication → OAuth
OAuth Provider: Custom
Client ID: portainer
Client Secret: <secret>
Authorization URL: https://auth.home.lewelly.com/api/oidc/authorization
Access Token URL: https://auth.home.lewelly.com/api/oidc/token
Resource URL: https://auth.home.lewelly.com/api/oidc/userinfo
Redirect URL: https://portainer.home.lewelly.com/
User Identifier: preferred_username
Scopes: openid profile email groups
```

---

### Proxmox

**Callback**: `https://proxmox.home.lewelly.com:8006/api2/oidc/callback`

```bash
# Via Proxmox shell
pveum realm add authelia --type openid \
  --issuer-url https://auth.home.lewelly.com \
  --client-id proxmox \
  --client-key <secret> \
  --username-claim preferred_username \
  --scopes "openid profile email" \
  --autocreate 1
```

---

## Group-to-Role Mapping Examples

### Simple Admin/Viewer

```yaml
role_attribute_path: contains(groups[*], 'admins') && 'Admin' || 'Viewer'
```

### Admin/Editor/Viewer

```yaml
role_attribute_path: |
  contains(groups[*], 'admins') && 'Admin' ||
  contains(groups[*], 'developers') && 'Editor' ||
  'Viewer'
```

### Multiple Admin Groups

```yaml
role_attribute_path: |
  (contains(groups[*], 'admins') || contains(groups[*], 'sysadmins')) && 'Admin' ||
  contains(groups[*], 'developers') && 'Editor' ||
  'Viewer'
```

### Custom App-Specific Groups

```yaml
role_attribute_path: |
  contains(groups[*], 'grafana-admins') && 'Admin' ||
  contains(groups[*], 'grafana-editors') && 'Editor' ||
  contains(groups[*], 'grafana-viewers') && 'Viewer' ||
  'Viewer'
```

## Access Control Patterns

### Public App (Authenticated Users)

```yaml
access_control:
  rules:
    - domain: app.home.lewelly.com
      policy: one_factor  # Any authenticated user
```

### Restricted to Admins Only

```yaml
access_control:
  rules:
    - domain: admin-app.home.lewelly.com
      policy: one_factor
      subject:
        - "group:admins"
```

### Multiple Groups

```yaml
access_control:
  rules:
    - domain: dev-app.home.lewelly.com
      policy: one_factor
      subject:
        - "group:admins"
        - "group:developers"
```

### Specific Users

```yaml
access_control:
  rules:
    - domain: personal-app.home.lewelly.com
      policy: one_factor
      subject:
        - "user:alice"
        - "user:bob"
```

### Network-Based

```yaml
access_control:
  rules:
    - domain: internal-app.home.lewelly.com
      policy: one_factor
      networks:
        - 192.168.1.0/24  # Home network only
```

## Useful Commands

### Test OIDC Discovery

```bash
curl -s https://auth.home.lewelly.com/.well-known/openid-configuration | jq
```

### Check Authelia Logs

```bash
kubectl logs -n authelia -l app.kubernetes.io/name=authelia --tail=100 -f
```

### Verify Client Registration

```bash
kubectl logs -n authelia -l app.kubernetes.io/name=authelia | grep "client_id"
```

### Test UserInfo Endpoint

```bash
# Get token from browser dev tools after login, then:
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  https://auth.home.lewelly.com/api/oidc/userinfo | jq
```

### Restart Authelia

```bash
kubectl rollout restart deployment -n authelia authelia
```

### View OIDC Secrets

```bash
sops infrastructure/authelia/authelia-secrets.yaml
```

## Troubleshooting Quick Checks

### ✓ Client ID exists in Authelia config

```bash
grep -A 5 "client_id: app-name" infrastructure/authelia/authelia.yaml
```

### ✓ Secret exists in Authelia secrets

```bash
sops -d infrastructure/authelia/authelia-secrets.yaml | grep "app-name-client-secret"
```

### ✓ Redirect URI matches exactly

```bash
# Compare application logs with Authelia config
kubectl logs -n app-namespace app-pod | grep redirect_uri
grep -A 10 "client_id: app-name" infrastructure/authelia/authelia.yaml
```

### ✓ Access control allows domain

```bash
grep -A 5 "domain: app.home.lewelly.com" infrastructure/authelia/authelia.yaml
```

### ✓ Scopes include required claims

```bash
# Should include: openid (required), profile, email, groups (if needed)
grep -A 15 "client_id: app-name" infrastructure/authelia/authelia.yaml | grep scopes -A 5
```

## Security Checklist

- [ ] Client secret is cryptographically random (32+ bytes)
- [ ] Redirect URIs are exact matches (no wildcards)
- [ ] All URLs use HTTPS
- [ ] Access control rule exists for domain
- [ ] Appropriate `authorization_policy` (one_factor, two_factor, bypass)
- [ ] Secrets are encrypted with SOPS
- [ ] Application validates TLS certificates
- [ ] Token lifetime is reasonable (<1 hour recommended)
- [ ] Groups claim is used if RBAC needed
- [ ] Test user can successfully authenticate

## Common Error Messages

| Error                        | Cause               | Solution                             |
| ---------------------------- | ------------------- | ------------------------------------ |
| "invalid redirect_uri"       | URI mismatch        | Check redirect_uris in client config |
| "invalid client credentials" | Secret mismatch     | Verify secret in both places         |
| "access forbidden"           | Access control      | Check access_control rules           |
| "invalid scope"              | Unsupported scope   | Use: openid, profile, email, groups  |
| "unable to verify token"     | JWKS issue          | Verify /jwks.json is accessible      |
| CORS error                   | Missing CORS config | Add cors.allowed_origins in Authelia |

## File Locations Quick Reference

```raw
infrastructure/authelia/
  ├── authelia.yaml              # Add clients here
  └── authelia-secrets.yaml      # Add client secrets here (SOPS encrypted)

infrastructure/monitoring/
  ├── prometheus/
  │   └── kube-prometheus-stack.yaml  # Grafana OIDC config
  └── grafana-oidc-secret.yaml   # Grafana OIDC secret

apps/base/<app>/
  └── <app>.yaml                 # App-specific OIDC config
```

## Validation Workflow

```bash
# 1. Make changes
vim infrastructure/authelia/authelia.yaml
sops infrastructure/authelia/authelia-secrets.yaml

# 2. Validate
make validate

# 3. Commit
git add infrastructure/authelia/
git commit -m "feat: add OIDC for <app>"

# 4. Deploy
git push

# 5. Monitor
make watch

# 6. Test
curl https://app.home.lewelly.com
```

---

**Quick Links:**

- Full Guide: [`OIDC_INTEGRATION_GUIDE.md`](./OIDC_INTEGRATION_GUIDE.md)
- Grafana Setup: [`GRAFANA_OIDC_QUICKSTART.md`](./GRAFANA_OIDC_QUICKSTART.md)
- Main Deployment: [`../DEPLOYMENT_SUMMARY.md`](../DEPLOYMENT_SUMMARY.md)

**Last Updated**: 2025-11-15
