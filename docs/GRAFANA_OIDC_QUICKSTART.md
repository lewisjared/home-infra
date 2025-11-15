# Grafana OIDC Integration - Quick Start

This is a step-by-step guide to integrate your existing Grafana deployment with Authelia SSO.

## Prerequisites

- ✅ Authelia is running at `https://auth.home.lewelly.com`
- ✅ Grafana is accessible (currently via direct login)
- ✅ You have admin access to the repository

## Step-by-Step Integration

### 1. Generate Client Secret

```bash
openssl rand -base64 32
```

**Example output**: `XyZ789AbC123dEf456GhI789JkL012MnO345PqR678==`

💾 **Save this** - you'll use it in steps 2 and 5!

---

### 2. Add OIDC Client to Authelia

Edit `infrastructure/authelia/authelia.yaml` and add Grafana as a client:

```bash
vim infrastructure/authelia/authelia.yaml
```

Find the `configMap.identity_providers.oidc.clients` section and add:

```yaml
configMap:
  identity_providers:
    oidc:
      clients:
        # ... existing clients like headlamp ...

        # Add this new client:
        - client_id: grafana
          client_name: Grafana Monitoring Dashboard
          client_secret:
            path: grafana-client-secret
          public: false
          authorization_policy: one_factor
          redirect_uris:
            - https://grafana.home.lewelly.com/login/generic_oauth
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
```

---

### 3. Add Access Control Rule

In the same file, find `configMap.access_control.rules` and add:

```yaml
configMap:
  access_control:
    default_policy: deny
    rules:
      # ... existing rules ...

      # Add Grafana access rule
      - domain: grafana.home.lewelly.com
        policy: one_factor
```

---

### 4. Add Client Secret to Authelia Secrets

Decrypt and edit the secrets:

```bash
sops infrastructure/authelia/authelia-secrets.yaml
```

Add your client secret (from Step 1):

```yaml
stringData:
  # ... existing secrets ...
  grafana-client-secret: XyZ789AbC123dEf456GhI789JkL012MnO345PqR678==
```

Save and exit (SOPS will auto-encrypt).

---

### 5. Configure Grafana for OIDC

Your Grafana is deployed via the `kube-prometheus-stack` Helm chart. Edit:

```bash
vim infrastructure/monitoring/prometheus/kube-prometheus-stack.yaml
```

Find the `grafana:` section and update it:

```yaml
values:
  grafana:
    # ... existing config ...

    # Update root URL
    grafana.ini:
      server:
        root_url: https://grafana.home.lewelly.com

      # Add OIDC configuration
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
        # Map Authelia groups to Grafana roles
        role_attribute_path: contains(groups[*], 'admins') && 'Admin' || contains(groups[*], 'developers') && 'Editor' || 'Viewer'
        allow_sign_up: true
        auto_login: false  # Set to true to skip Grafana login screen

      # Keep analytics disabled
      analytics:
        check_for_updates: false

      # Keep embedding allowed
      security:
        allow_embedding: true

    # Add environment variable from secret
    envFromSecrets:
      - name: grafana-oidc-env
        optional: false

    # ... rest of existing config ...
```

**Role Mapping Explained:**
- Users in `admins` group → Grafana Admin (full access)
- Users in `developers` group → Grafana Editor (can create dashboards)
- All other authenticated users → Grafana Viewer (read-only)

---

### 6. Create Grafana OIDC Secret

Create a new file for the Grafana OIDC secret:

```bash
vim infrastructure/monitoring/grafana-oidc-secret.yaml
```

Add this content (using the secret from Step 1):

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-oidc-env
  namespace: monitoring
type: Opaque
stringData:
  GRAFANA_OIDC_CLIENT_SECRET: XyZ789AbC123dEf456GhI789JkL012MnO345PqR678==
```

Encrypt it with SOPS:

```bash
sops --encrypt --in-place infrastructure/monitoring/grafana-oidc-secret.yaml
```

---

### 7. Update Monitoring Kustomization

Add the new secret to the monitoring kustomization:

```bash
vim infrastructure/monitoring/kustomization.yaml
```

Add to resources:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: monitoring
resources:
  - namespace.yaml
  - prometheus/kustomization.yaml
  - loki/kustomization.yaml
  - tempo/kustomization.yaml
  - alloy/kustomization.yaml
  - dashboards/kustomization.yaml
  - sources/kustomization.yaml
  - ingresses/kustomization.yaml
  - network-policies/kustomization.yaml
  - grafana-oidc-secret.yaml  # Add this line
```

---

### 8. Validate Changes

Before committing, validate all manifests:

```bash
make validate
```

You should see:
```
✓ All 13 Helm charts validated successfully
✓ All Kustomize overlays valid
```

---

### 9. Commit and Deploy

```bash
# Stage all changes
git add \
  infrastructure/authelia/authelia.yaml \
  infrastructure/authelia/authelia-secrets.yaml \
  infrastructure/monitoring/prometheus/kube-prometheus-stack.yaml \
  infrastructure/monitoring/grafana-oidc-secret.yaml \
  infrastructure/monitoring/kustomization.yaml

# Commit
git commit -m "feat: integrate Grafana with Authelia OIDC

- Add Grafana as OIDC client in Authelia
- Configure Grafana generic OAuth with Authelia endpoints
- Map Authelia groups to Grafana roles (admins→Admin, developers→Editor)
- Add access control rule for grafana.home.lewelly.com"

# Push to trigger Flux deployment
git push

# Watch deployment
make watch
```

---

### 10. Test the Integration

1. **Wait for Grafana to restart** (~1-2 minutes):
   ```bash
   kubectl rollout status deployment -n monitoring prometheus-grafana
   ```

2. **Navigate to Grafana**:
   ```
   https://grafana.home.lewelly.com
   ```

3. **You should see a new login option**: "Sign in with Authelia"

4. **Click it** and you'll be redirected to Authelia

5. **Log in** with your credentials + 2FA

6. **You'll be redirected back** to Grafana, logged in!

---

## Verification Checklist

After deployment, verify:

- [ ] Grafana pod restarted successfully
- [ ] Can access `https://grafana.home.lewelly.com`
- [ ] "Sign in with Authelia" button appears on login page
- [ ] Clicking button redirects to Authelia
- [ ] After Authelia login, redirected back to Grafana
- [ ] User role matches group (admin/editor/viewer)
- [ ] Can access dashboards according to role

Check status:

```bash
# Grafana pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Grafana logs (look for OAuth initialization)
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50

# Authelia logs (look for Grafana client requests)
kubectl logs -n authelia -l app.kubernetes.io/name=authelia --tail=50 | grep grafana
```

---

## Role Mapping Examples

### Default Mapping (Current)

```yaml
role_attribute_path: |
  contains(groups[*], 'admins') && 'Admin' ||
  contains(groups[*], 'developers') && 'Editor' ||
  'Viewer'
```

| Authelia Group | Grafana Role | Permissions |
|----------------|--------------|-------------|
| `admins` | Admin | Full access, manage users, datasources |
| `developers` | Editor | Create/edit dashboards, no user management |
| Others | Viewer | Read-only access |

### Alternative: Everyone is Editor

```yaml
role_attribute_path: contains(groups[*], 'admins') && 'Admin' || 'Editor'
```

### Alternative: Separate Groups

Add new groups in `infrastructure/authelia/users-database.yaml`:

```yaml
users:
  admin:
    groups:
      - admins
      - grafana-admins

  developer:
    groups:
      - developers
      - grafana-editors

  viewer:
    groups:
      - viewers
      - grafana-viewers
```

Then use specific Grafana groups:

```yaml
role_attribute_path: |
  contains(groups[*], 'grafana-admins') && 'Admin' ||
  contains(groups[*], 'grafana-editors') && 'Editor' ||
  'Viewer'
```

---

## Troubleshooting

### Problem: "Sign in with Authelia" button doesn't appear

**Solution**: Check Grafana configuration was applied:

```bash
# Check Grafana pod environment
kubectl exec -n monitoring deployment/prometheus-grafana -- env | grep OIDC

# Should show: GRAFANA_OIDC_CLIENT_SECRET=...

# Check Grafana config
kubectl exec -n monitoring deployment/prometheus-grafana -- cat /etc/grafana/grafana.ini | grep -A 20 "auth.generic_oauth"
```

If not present, Grafana pod may not have restarted:

```bash
kubectl rollout restart deployment -n monitoring prometheus-grafana
```

---

### Problem: Redirect loop after login

**Solution**: Verify redirect URI matches exactly:

```bash
# In Authelia config, should be:
redirect_uris:
  - https://grafana.home.lewelly.com/login/generic_oauth

# Not:
# - https://grafana.home.lewelly.com/  (wrong!)
```

Check Grafana logs:

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100 | grep -i oauth
```

---

### Problem: "Invalid client credentials"

**Solution**: Client secret mismatch. Verify:

1. Secret in `authelia-secrets.yaml` matches secret in `grafana-oidc-secret.yaml`
2. Authelia pod restarted after secret change:
   ```bash
   kubectl rollout restart deployment -n authelia authelia
   ```

---

### Problem: User has wrong role (always Viewer)

**Solution**: Groups not being passed. Check:

1. `groups` scope is in client config ✓
2. User has groups in `users-database.yaml`:
   ```bash
   sops infrastructure/authelia/users-database.yaml
   # Verify user has: groups: [admins]
   ```
3. Test UserInfo endpoint:
   ```bash
   # Login to Grafana, then check browser dev tools → Network
   # Find call to /api/oidc/userinfo
   # Response should include: "groups": ["admins"]
   ```

---

### Problem: Want to disable local Grafana login

**Solution**: Set `auto_login: true` and `disable_login_form: true`:

```yaml
auth.generic_oauth:
  auto_login: true  # Auto-redirect to Authelia

auth:
  disable_login_form: true  # Hide username/password fields
```

⚠️ **Warning**: This means you can ONLY login via OIDC. If Authelia is down, you can't access Grafana!

**Safer approach**: Keep local admin account as backup:

```yaml
auth:
  disable_login_form: false  # Keep local login available

# But disable sign-up
auth.generic_oauth:
  allow_sign_up: true
  auto_assign_org: true
  auto_assign_org_role: Viewer  # Default role for new users
```

---

## Advanced Configuration

### Auto-provision Teams

Map Authelia groups to Grafana teams:

```yaml
auth.generic_oauth:
  team_ids_attribute_path: groups
  teams_attribute_path: groups
```

### Enable Group Sync

Sync group membership on every login:

```yaml
auth.generic_oauth:
  sync_teams: true
  skip_org_role_sync: false
```

### Custom Claim Mapping

Use custom claims from Authelia:

```yaml
auth.generic_oauth:
  role_attribute_path: |
    contains(groups[*], 'admins') && 'Admin' ||
    contains(groups[*], 'developers') && 'Editor' ||
    contains(groups[*], 'operators') && 'Editor' ||
    'Viewer'

  login_attribute_path: preferred_username
  name_attribute_path: name
  email_attribute_path: email
```

---

## Reverting Changes

If you need to revert to local authentication:

1. Set `auth.generic_oauth.enabled: false` in `kube-prometheus-stack.yaml`
2. Remove the `envFromSecrets` section
3. Commit and push
4. Grafana will restart with local auth only

---

## Next Steps

Now that Grafana has SSO:

1. ✅ Add more users in Authelia (see main docs)
2. ✅ Configure group-based dashboard permissions
3. ✅ Integrate other applications (Harbor, ArgoCD, etc.)
4. ✅ Set up Grafana alerting with proper user context

---

**Need Help?**

- Check main OIDC integration guide: `docs/OIDC_INTEGRATION_GUIDE.md`
- Review Authelia logs: `kubectl logs -n authelia -l app.kubernetes.io/name=authelia`
- Check Grafana logs: `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana`

**Last Updated**: 2025-11-15
