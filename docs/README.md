# Documentation

This directory contains documentation for the home-infra Kubernetes cluster.

## Getting Started

- **[Deployment Summary](../DEPLOYMENT_SUMMARY.md)** - Overview of Headlamp and Authelia deployment
- **[Main README](../README.md)** - Repository overview and architecture

## Infrastructure

- **[Cilium](./CILIUM.md)** - CNI plugin (networking, security, Hubble observability, upgrade process)
- **[DNS](./DNS.md)** - Technitium DNS cluster (authoritative DNS, ad blocking, external-dns integration)

## OIDC / SSO Integration

Authelia is configured as the central OIDC provider for Single Sign-On across all applications.

### Documentation

1. **[OIDC Integration Guide](./OIDC_INTEGRATION_GUIDE.md)** 📚
   - Complete guide to integrating any application with Authelia
   - Covers the full integration process
   - Generic examples and troubleshooting
   - Security best practices
   - **Start here** if you're new to OIDC integration

2. **[Grafana OIDC Quick Start](./GRAFANA_OIDC_QUICKSTART.md)** 🚀
   - Step-by-step Grafana integration
   - Copy-paste ready examples
   - Specific to the kube-prometheus-stack deployment
   - Role mapping examples
   - **Start here** if you want to integrate Grafana

3. **[OIDC Quick Reference](./OIDC_QUICK_REFERENCE.md)** ⚡
   - One-page reference for common integrations
   - Application-specific callback URLs
   - Configuration templates
   - Troubleshooting checklist
   - **Start here** for quick lookups

### Integration Workflow

```raw
┌─────────────────────────────────────────────────────┐
│ 1. Read Integration Guide                          │
│    → Understand the process                        │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ 2. Check Quick Reference                           │
│    → Find app-specific callback URL                │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ 3. Follow Integration Steps                        │
│    → Add client to Authelia                        │
│    → Add secret                                     │
│    → Configure application                         │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ 4. Validate & Deploy                               │
│    → make validate                                  │
│    → git commit && git push                        │
└─────────────────────────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│ 5. Test Integration                                │
│    → Access app → redirected to Authelia           │
└─────────────────────────────────────────────────────┘
```

## Quick Start Examples

### Integrating a New Application

Most common scenario - you have an app and want to add OIDC:

```bash
# 1. Generate secret
openssl rand -base64 32

# 2. Edit Authelia config
vim infrastructure/authelia/authelia.yaml
# Add client under configMap.identity_providers.oidc.clients

# 3. Add secret
sops infrastructure/authelia/authelia-secrets.yaml
# Add: app-name-client-secret: YOUR_SECRET

# 4. Add access control rule
# In same authelia.yaml under configMap.access_control.rules

# 5. Configure your application
# Use Quick Reference for app-specific settings

# 6. Deploy
make validate && git add . && git commit -m "feat: add OIDC for app" && git push
```

### Adding Grafana (Specific Example)

```bash
# Use the Grafana Quick Start guide - it has all the specific values
# for the kube-prometheus-stack integration
cat docs/GRAFANA_OIDC_QUICKSTART.md
```

## Architecture

### Current OIDC Setup

```raw
┌─────────────────────────────────────────────────────────┐
│                    User Browser                         │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 1. Access app URL
               ↓
┌─────────────────────────────────────────────────────────┐
│              Application (e.g., Grafana)                │
│  - Checks: is user authenticated?                       │
│  - No → redirect to Authelia                           │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 2. Redirect to auth endpoint
               ↓
┌─────────────────────────────────────────────────────────┐
│         Authelia (auth.home.lewelly.com)                │
│  - Login page                                           │
│  - Username + Password                                  │
│  - TOTP 2FA                                             │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 3. Return authorization code
               ↓
┌─────────────────────────────────────────────────────────┐
│              Application (e.g., Grafana)                │
│  - Exchange code for token                              │
│  - Validate token with Authelia                        │
│  - Extract user info & groups                          │
└──────────────┬──────────────────────────────────────────┘
               │
               │ 4. Map groups → roles
               ↓
┌─────────────────────────────────────────────────────────┐
│           Application Access Granted                    │
│  - admins → Admin                                       │
│  - developers → Editor                                  │
│  - others → Viewer                                      │
└─────────────────────────────────────────────────────────┘
```

### Integrated Applications

| Application | Status             | URL                                 | Groups Supported |
| ----------- | ------------------ | ----------------------------------- | ---------------- |
| Headlamp    | ✅ Deployed        | `https://headlamp.home.lewelly.com` | ✅ Yes           |
| Grafana     | 📝 Guide Available | `https://grafana.home.lewelly.com`  | ✅ Yes           |
| Harbor      | 📖 See Quick Ref   | -                                   | ✅ Yes           |

## Authelia Configuration

### Key Files

```raw
infrastructure/authelia/
├── authelia.yaml              # Main config (OIDC clients, access control)
├── authelia-secrets.yaml      # Secrets (SOPS encrypted)
├── users-database.yaml        # Users and groups (SOPS encrypted)
├── namespace.yaml
└── kustomization.yaml

clusters/home/
└── authelia.yaml              # Flux Kustomization
```

### Current OIDC Clients

- **headlamp**: Kubernetes UI dashboard
- **grafana**: (To be added) Monitoring dashboard

### Current User Groups

- **admins**: Full cluster admin access
- **developers**: Editor/contributor access
- **viewers**: Read-only access (if created)

## User Management

### Adding Users

```bash
# 1. Edit users database
sops infrastructure/authelia/users-database.yaml

# 2. Generate password hash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 \
  --password 'NewUserPassword' --config /dev/null

# 3. Add user
users:
  newuser:
    displayname: "New User Name"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."
    email: newuser@home.local
    groups:
      - developers

# 4. Commit and deploy
git add infrastructure/authelia/users-database.yaml
git commit -m "feat: add new user"
git push
```

### Modifying Groups

Groups control:

- **Access**: Which apps users can access (via access_control rules)
- **Roles**: What permissions users have (via role mapping in each app)

Example:

```yaml
# Authelia groups
users:
  alice:
    groups:
      - admins # Full access everywhere
      - grafana-editors # Can edit in Grafana specifically

# Access control (who can access)
access_control:
  rules:
    - domain: grafana.home.lewelly.com
      policy: one_factor
      subject:
        - "group:admins"
        - "group:grafana-editors" # Alice can access

# Role mapping in Grafana (what they can do)
role_attribute_path: |
  contains(groups[*], 'admins') && 'Admin' ||
  contains(groups[*], 'grafana-editors') && 'Editor' ||
  'Viewer'

# Result: Alice is Editor in Grafana
```

## Troubleshooting

### Common Issues

1. **Can't access application after OIDC setup**
   - Check access control rules in `authelia.yaml`
   - Verify user has required group membership
   - Check Authelia logs: `kubectl logs -n authelia -l app.kubernetes.io/name=authelia`

2. **Redirect loop after login**
   - Verify redirect URI exactly matches in both configs
   - Check application logs for actual redirect URI used
   - Ensure HTTPS is used everywhere

3. **Groups not working / wrong role assigned**
   - Verify `groups` scope is in client config
   - Check user has groups in `users-database.yaml`
   - Test UserInfo endpoint to see what claims are returned

4. **Client secret invalid**
   - Ensure secret matches in both places
   - Restart Authelia pod after secret changes
   - Check SOPS decryption is working

### Debug Commands

```bash
# View Authelia logs
kubectl logs -n authelia -l app.kubernetes.io/name=authelia --tail=100 -f

# Test OIDC discovery
curl https://auth.home.lewelly.com/.well-known/openid-configuration | jq

# Check if Authelia is ready
kubectl get pods -n authelia

# Verify secrets decrypted correctly
kubectl get secret -n authelia authelia-secrets -o yaml

# Manual secret check
sops -d infrastructure/authelia/authelia-secrets.yaml | grep -A 1 "app-client-secret"
```

## Security Considerations

### Current Security Posture

- ✅ All traffic encrypted (TLS via Let's Encrypt)
- ✅ 2FA enforced (TOTP)
- ✅ Password hashing (Argon2id)
- ✅ Secrets encrypted at rest (SOPS + PGP)
- ✅ RBAC based on groups
- ✅ Session cookies httpOnly + secure
- ✅ Access control per domain

### Best Practices

1. **Secrets Management**
   - Always use `openssl rand -base64 32` for secrets
   - Never commit unencrypted secrets
   - Rotate secrets every 90-180 days

2. **Access Control**
   - Default policy: deny
   - Explicitly allow domains
   - Use groups for authorization

3. **User Management**
   - Enforce 2FA for all users
   - Use strong passwords (Argon2id hashing)
   - Regular access reviews

4. **Application Security**
   - Verify TLS certificates
   - Use HTTPS for all redirect URIs
   - Validate OIDC tokens properly

## Additional Resources

### External Documentation

- [Authelia Documentation](https://www.authelia.com/)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [OAuth 2.0 RFC](https://datatracker.ietf.org/doc/html/rfc6749)

### Community

- [Authelia Discord](https://discord.gg/authelia)
- [GitHub Discussions](https://github.com/authelia/authelia/discussions)

## Contributing

When adding new integrations:

1. Test the integration thoroughly
2. Document the process
3. Add to Quick Reference if it's a common app
4. Update this README with the new app status
5. Create a PR with clear description

## Changelog

### 2025-11-15

- Initial documentation structure
- Added OIDC Integration Guide
- Added Grafana Quick Start
- Added OIDC Quick Reference
- Documented Headlamp integration

---

**Questions?** Check the integration guides or review Authelia logs for detailed error messages.
