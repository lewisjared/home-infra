# OIDC Integration Guide

This guide explains how to integrate applications with Authelia for Single Sign-On (SSO) authentication.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Integration Process](#integration-process)
- [Example: Grafana](#example-grafana)
- [Example: Generic Application](#example-generic-application)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Overview

Authelia is configured as an OIDC provider at `https://auth.home.lewelly.com`.
Any application that supports OIDC/OAuth2 can authenticate users through Authelia.

### What You Get

- **Single Sign-On**: Users log in once to Authelia and access all integrated apps
- **2FA Protection**: TOTP 2FA is enforced for all logins
- **Centralized User Management**: Add/remove users in one place
- **Group-Based Access**: Control access using Authelia groups
- **Audit Trail**: All authentication events are logged

## Prerequisites

Before integrating an application:

1. ✅ Authelia is deployed and accessible at `https://auth.home.lewelly.com`
2. ✅ The application supports OIDC/OAuth2 authentication
3. ✅ You have access to modify Authelia configuration
4. ✅ The application has an ingress with a hostname (e.g., `grafana.home.lewelly.com`)

## Integration Process

### Step 1: Generate Client Secret

Generate a secure random secret for your application:

```bash
openssl rand -base64 32
```

Save this output - you'll need it in Steps 2 and 3.

### Step 2: Register Application in Authelia

Edit the Authelia configuration to add your application as an OIDC client:

```bash
# Open the Authelia HelmRelease
vim infrastructure/authelia/authelia.yaml
```

Add a new client under `configMap.identity_providers.oidc.clients`:

```yaml
configMap:
  identity_providers:
    oidc:
      enabled: true
      jwks:
        - key_id: default
          algorithm: RS256
          use: sig
          key:
            path: /secrets/oidc-private-key
      clients:
        # ... existing clients (like headlamp)

        # Your new application
        - client_id: your-app-name # Unique identifier (e.g., "grafana")
          client_name: Your App Display Name
          client_secret:
            path: your-app-client-secret # Must match Step 3 secret name
          public: false
          authorization_policy: one_factor # Requires login + 2FA
          redirect_uris:
            - https://your-app.home.lewelly.com/login/generic_oauth # App's callback URL
          scopes:
            - openid
            - profile
            - email
            - groups # Include if app needs group info
          grant_types:
            - authorization_code
          response_types:
            - code
          response_modes:
            - form_post
            - query
          userinfo_signed_response_alg: none
```

**Important Fields:**

- `client_id`: Unique identifier (use app name in lowercase)
- `client_secret.path`: Key name in the Authelia secrets (Step 3)
- `redirect_uris`: Callback URL(s) from your application
- `authorization_policy`:
  - `one_factor`: Login + 2FA required
  - `two_factor`: Login + 2FA required (same as one_factor)
  - `bypass`: No authentication (not recommended)

### Step 3: Add Client Secret to Authelia Secrets

Decrypt and edit the Authelia secrets file:

```bash
sops infrastructure/authelia/authelia-secrets.yaml
```

Add your application's client secret:

```yaml
stringData:
  # ... existing secrets
  your-app-client-secret: "paste-secret-from-step-1"
```

Save the file (SOPS will auto-encrypt).

### Step 4: Add Access Control Rule

In the same `authelia.yaml` file, add an access control rule:

```yaml
configMap:
  access_control:
    default_policy: deny
    rules:
      # ... existing rules

      # Your application
      - domain: your-app.home.lewelly.com
        policy: one_factor # Requires authentication
        # Optional: restrict to specific groups
        # subject:
        #   - "group:admins"
```

**Policy Options:**

- `bypass`: No authentication required
- `one_factor`: Requires login + 2FA
- `two_factor`: Same as one_factor
- `deny`: Explicitly deny access

### Step 5: Configure Application

Each application is different, but generally you need to configure:

- **OIDC Issuer URL**: `https://auth.home.lewelly.com`
- **Client ID**: `your-app-name` (from Step 2)
- **Client Secret**: The secret from Step 1
- **Redirect URI**: `https://your-app.home.lewelly.com/callback`
- **Scopes**: `openid profile email groups`

See application-specific examples below.

### Step 6: Commit and Deploy

```bash
# Verify changes are valid
make validate

# Commit changes
git add infrastructure/authelia/authelia.yaml infrastructure/authelia/authelia-secrets.yaml
git commit -m "feat: add OIDC integration for YourApp"
git push

# Watch Flux deploy
make watch
```

### Step 7: Test Integration

1. Navigate to your application's URL
2. Click "Login with SSO" or equivalent
3. You should be redirected to Authelia
4. Log in with your credentials + 2FA
5. You should be redirected back to the application, logged in

---

## Example: Grafana

Here's a complete example of integrating Grafana with Authelia OIDC.

### Step 1: Generate Secret

```bash
openssl rand -base64 32
# Output: abc123xyz789example==
```

### Step 2: Update Authelia Configuration

Edit `infrastructure/authelia/authelia.yaml`:

```yaml
configMap:
  identity_providers:
    oidc:
      enabled: true
      jwks:
        - key_id: default
          algorithm: RS256
          use: sig
          key:
            path: /secrets/oidc-private-key
      clients:
        # ... existing clients ...

        - client_id: grafana
          client_name: Grafana Dashboard
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

Add access control rule:

```yaml
configMap:
  access_control:
    default_policy: deny
    rules:
      # ... existing rules ...

      - domain: grafana.home.lewelly.com
        policy: one_factor
```

### Step 3: Add Secret to Authelia

```bash
sops infrastructure/authelia/authelia-secrets.yaml
```

Add:

```yaml
stringData:
  # ... existing secrets ...
  grafana-client-secret: abc123xyz789example==
```

### Step 4: Configure Grafana

Edit your Grafana HelmRelease (likely `infrastructure/monitoring/prometheus/kube-prometheus-stack.yaml`):

```yaml
values:
  grafana:
    # ... existing config ...

    grafana.ini:
      server:
        root_url: https://grafana.home.lewelly.com

      auth.generic_oauth:
        enabled: true
        name: Authelia
        client_id: grafana
        client_secret: ${GRAFANA_OIDC_CLIENT_SECRET} # From secret
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
        auto_login: false # Set to true to skip Grafana login page

    # Mount the OIDC client secret as environment variable
    envFromSecret: grafana-oidc-secret
```

### Step 5: Create Grafana OIDC Secret

Create `infrastructure/monitoring/grafana-oidc-secret.yaml`:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-oidc-secret
  namespace: monitoring
type: Opaque
stringData:
  GRAFANA_OIDC_CLIENT_SECRET: abc123xyz789example==
```

Encrypt it:

```bash
sops --encrypt --in-place infrastructure/monitoring/grafana-oidc-secret.yaml
```

Add to `infrastructure/monitoring/kustomization.yaml`:

```yaml
resources:
  # ... existing resources ...
  - grafana-oidc-secret.yaml
```

### Step 6: Configure Role Mapping

The `role_attribute_path` in Step 4 maps Authelia groups to Grafana roles:

- Users in `admins` group → Grafana Admin
- All other users → Grafana Viewer

To make developers editors:

```yaml
role_attribute_path: |
  contains(groups[*], 'admins') && 'Admin' ||
  contains(groups[*], 'developers') && 'Editor' ||
  'Viewer'
```

### Step 7: Deploy

```bash
make validate
git add infrastructure/authelia/authelia.yaml \
        infrastructure/authelia/authelia-secrets.yaml \
        infrastructure/monitoring/prometheus/kube-prometheus-stack.yaml \
        infrastructure/monitoring/grafana-oidc-secret.yaml \
        infrastructure/monitoring/kustomization.yaml
git commit -m "feat: add Authelia OIDC integration for Grafana"
git push
make watch
```

### Step 8: Test

1. Go to `https://grafana.home.lewelly.com`
2. Click "Sign in with Authelia"
3. Log in with Authelia credentials + 2FA
4. You should be redirected back to Grafana as an authenticated user

---

## Example: Generic Application

For applications that support standard OIDC:

### Required Configuration Values

Provide these to your application:

| Setting                    | Value                                                            |
| -------------------------- | ---------------------------------------------------------------- |
| **Discovery URL**          | `https://auth.home.lewelly.com/.well-known/openid-configuration` |
| **Issuer URL**             | `https://auth.home.lewelly.com`                                  |
| **Authorization Endpoint** | `https://auth.home.lewelly.com/api/oidc/authorization`           |
| **Token Endpoint**         | `https://auth.home.lewelly.com/api/oidc/token`                   |
| **UserInfo Endpoint**      | `https://auth.home.lewelly.com/api/oidc/userinfo`                |
| **JWKS URI**               | `https://auth.home.lewelly.com/jwks.json`                        |
| **Client ID**              | `your-app-name`                                                  |
| **Client Secret**          | (generated in Step 1)                                            |
| **Scopes**                 | `openid profile email groups`                                    |
| **Response Type**          | `code`                                                           |
| **Grant Type**             | `authorization_code`                                             |

### Testing OIDC Discovery

Verify Authelia's OIDC configuration is accessible:

```bash
curl https://auth.home.lewelly.com/.well-known/openid-configuration | jq
```

Expected response includes:

```json
{
  "issuer": "https://auth.home.lewelly.com",
  "authorization_endpoint": "https://auth.home.lewelly.com/api/oidc/authorization",
  "token_endpoint": "https://auth.home.lewelly.com/api/oidc/token",
  "userinfo_endpoint": "https://auth.home.lewelly.com/api/oidc/userinfo",
  "jwks_uri": "https://auth.home.lewelly.com/jwks.json",
  ...
}
```

---

## Troubleshooting

### Redirect URI Mismatch

**Error**: "Invalid redirect URI"

**Solution**: Ensure the redirect URI in Authelia configuration exactly matches what the application sends:

```yaml
redirect_uris:
  - https://app.home.lewelly.com/callback # Exact match required
  - https://app.home.lewelly.com/oauth/callback # Can have multiple
```

Check your application's logs to see what redirect URI it's sending.

### Client Secret Invalid

**Error**: "Invalid client credentials"

**Solution**:

1. Verify the secret in `authelia-secrets.yaml` matches what you configured in the app
2. Ensure the secret path in the client config matches:

   ```yaml
   client_secret:
     path: app-name-client-secret # Must match key in authelia-secrets.yaml
   ```

3. Check Authelia pod has restarted after secret changes

### User Not Logged In / Session Issues

**Error**: Redirects to Authelia login repeatedly

**Solution**:

1. Check browser console for CORS errors
2. Verify session cookie domain matches:

   ```yaml
   session:
     cookies:
       - domain: home.lewelly.com # Should cover *.home.lewelly.com
   ```

3. Clear browser cookies for `*.home.lewelly.com`
4. Check application and Authelia are both using HTTPS

### Access Denied

**Error**: "Access forbidden" after successful login

**Solution**: Check the access control rule allows your user:

```yaml
access_control:
  rules:
    - domain: app.home.lewelly.com
      policy: one_factor
      # If you have subject restrictions:
      subject:
        - "group:admins" # User must be in admins group
```

Check user's groups in `users-database.yaml`.

### Groups Not Passed to Application

**Problem**: Application doesn't see user groups

**Solution**:

1. Ensure `groups` scope is included in client config:

   ```yaml
   scopes:
     - openid
     - profile
     - email
     - groups # Required for group info
   ```

2. Application must request groups scope
3. Check UserInfo endpoint response:

   ```bash
   # Get access token from browser dev tools, then:
   curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
     https://auth.home.lewelly.com/api/oidc/userinfo
   ```

### Debugging Tips

#### View Authelia Logs

```bash
kubectl logs -n authelia -l app.kubernetes.io/name=authelia --tail=100 -f
```

Look for:

- Client registration errors
- Redirect URI mismatches
- Access control denials
- Token validation errors

#### Check Application Logs

Most applications log OIDC errors. Look for:

- OAuth/OIDC error messages
- Token validation failures
- Network connection issues

#### Test OIDC Flow Manually

Use a tool like [oidc-debugger](https://oidcdebugger.com/) to test the flow:

1. Use Authelia's authorization endpoint
2. Set client ID, redirect URI, scopes
3. Walk through the flow step by step
4. Verify tokens are issued correctly

---

## Security Best Practices

### 1. Use Strong Client Secrets

Always generate cryptographically secure random secrets:

```bash
# Good: 32 bytes = 256 bits of entropy
openssl rand -base64 32

# Bad: weak, predictable
echo "password123"
```

### 2. Restrict Redirect URIs

Only allow exact redirect URIs you control:

```yaml
# Good: specific URLs
redirect_uris:
  - https://app.home.lewelly.com/callback

# Bad: wildcards or broad patterns
redirect_uris:
  - https://*.lewelly.com/*  # Too permissive!
```

### 3. Use HTTPS Only

Never use OIDC over HTTP in production:

- All redirect URIs must be HTTPS
- Authelia must be accessible over HTTPS
- Cookies are marked `secure`

### 4. Implement Proper Access Control

Use Authelia's access control to restrict access:

```yaml
access_control:
  rules:
    # Restrict admin apps to admins group
    - domain: admin-app.home.lewelly.com
      policy: one_factor
      subject:
        - "group:admins"

    # Public apps available to all authenticated users
    - domain: wiki.home.lewelly.com
      policy: one_factor
```

### 5. Enable 2FA for All Users

Ensure all users set up TOTP on first login:

```yaml
configMap:
  default_2fa_method: totp
```

### 6. Audit Access Regularly

Review Authelia logs for:

- Failed login attempts
- Unusual access patterns
- Token misuse

### 7. Rotate Secrets Periodically

Change client secrets every 90-180 days:

1. Generate new secret
2. Update application configuration with new secret
3. Update Authelia secrets
4. Test integration
5. Remove old secret from Authelia

### 8. Limit Token Lifetime

Configure short-lived tokens in application:

```yaml
# Example for Grafana
auth.generic_oauth:
  token_expiration: 3600 # 1 hour
```

### 9. Use Groups for RBAC

Map Authelia groups to application roles:

```yaml
# In application config
role_mapping:
  admins: Admin
  developers: Editor
  viewers: Viewer
```

### 10. Monitor Failed Authentications

Set up alerts for:

- Multiple failed login attempts
- Access denials
- Invalid client credentials

---

## Additional Examples

### Example Applications

Here are other common applications that can integrate with Authelia:

| Application   | Callback Path                         | Notes                      |
| ------------- | ------------------------------------- | -------------------------- |
| **Grafana**   | `/login/generic_oauth`                | Supports group-based roles |
| **Harbor**    | `/c/oidc/callback`                    | Container registry         |
| **Vault**     | `/ui/vault/auth/oidc/oidc/callback`   | Secrets management         |
| **GitLab**    | `/users/auth/openid_connect/callback` | Git platform               |
| **Nextcloud** | `/apps/user_oidc/code`                | File sharing               |
| **Portainer** | `/`                                   | Container management       |
| **Proxmox**   | `/api2/oidc/callback`                 | Virtualization             |

### Quick Reference: Common Callback URLs

```raw
Grafana:     https://<host>/login/generic_oauth
Harbor:      https://<host>/c/oidc/callback
Nextcloud:   https://<host>/apps/user_oidc/code
Portainer:   https://<host>/
GitLab:      https://<host>/users/auth/openid_connect/callback
```

---

## Getting Help

### Check Documentation

- [Authelia OIDC Documentation](https://www.authelia.com/configuration/identity-providers/openid-connect/)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)

### Community Resources

- Authelia Discord: <https://discord.gg/authelia>
- GitHub Issues: <https://github.com/authelia/authelia/issues>

### Common Issues Repository

Check the [Authelia FAQ](https://www.authelia.com/overview/prologue/faq/) for solutions to common problems.

---

**Last Updated**: 2025-11-15
**Authelia Version**: Latest (Helm Chart 0.9.x)
