# Headlamp + Authelia Deployment Summary

## What Was Deployed

### 1. Authelia (OIDC Provider)

- **Location**: `infrastructure/authelia/`
- **Namespace**: `authelia`
- **URL**: `https://auth.home.lewelly.com`
- **Components**:
  - Authelia server (lightweight SSO with OIDC)
  - Redis (session storage, no persistence)
  - File-based user database
  - SQLite storage for Authelia data
  - Let's Encrypt TLS certificate (via cert-manager)
  - Automatic DNS (via external-dns)

### 2. Headlamp (Kubernetes UI)

- **Location**: `apps/base/headlamp/` and `apps/home/headlamp/`
- **Namespace**: `headlamp`
- **URL**: `https://headlamp.home.lewelly.com`
- **Features**:
  - Full Kubernetes web UI (CNCF Sandbox project)
  - OIDC authentication via Authelia
  - Mobile-responsive design
  - RBAC-aware (adapts to user permissions)
  - Let's Encrypt TLS certificate (via cert-manager)
  - Automatic DNS (via external-dns)

## Access Information

### Default Credentials

- **Username**: `admin`
- **Password**: `admin`
- **Email**: `admin@home.local`

**IMPORTANT**: Change the password after first login!

### User Groups

The default admin user belongs to two groups:

- `admins`: Full cluster-admin access (via ClusterRoleBinding)
- `developers`: View-only access

## How to Access

1. **Wait for DNS and Certificates**:

   ```bash
   # Watch Flux reconcile
   make watch
   
   # Check DNS records
   nslookup auth.home.lewelly.com
   nslookup headlamp.home.lewelly.com
   
   # Verify certificates
   kubectl get certificate -n authelia
   kubectl get certificate -n headlamp
   ```

2. **Navigate to Authelia** first: `https://auth.home.lewelly.com`
   - Log in with credentials above
   - You'll be prompted to set up 2FA (TOTP) on first login
   - Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)

3. **Access Headlamp**: `https://headlamp.home.lewelly.com`
   - You'll be automatically redirected to Authelia for authentication
   - After successful auth + 2FA, you'll be redirected back to Headlamp
   - You'll have full cluster access based on your group memberships

## Architecture

```
User → https://headlamp.home.lewelly.com
  ↓
Headlamp redirects to Authelia
  ↓
User → https://auth.home.lewelly.com (login + 2FA)
  ↓
Authelia validates credentials and TOTP
  ↓
Authelia returns OIDC token to Headlamp
  ↓
Headlamp uses token to authenticate with Kubernetes API
  ↓
Kubernetes RBAC enforces permissions based on group membership
```

## File Structure Created

```
.sops.yaml                              # Updated to encrypt apps/ directory
clusters/home/authelia.yaml             # Flux Kustomization for Authelia

infrastructure/authelia/
  ├── namespace.yaml                    # Authelia namespace
  ├── authelia.yaml                     # HelmRelease and HelmRepository
  ├── authelia-secrets.yaml             # Encrypted secrets (SOPS)
  ├── users-database.yaml               # Encrypted user database (SOPS)
  └── kustomization.yaml                # Kustomization manifest

apps/base/headlamp/
  ├── namespace.yaml                    # Headlamp namespace
  ├── headlamp.yaml                     # HelmRelease and HelmRepository
  ├── rbac.yaml                         # ClusterRoleBindings for OIDC groups
  └── kustomization.yaml                # Kustomization manifest

apps/home/headlamp/
  ├── kustomization.yaml                # Home overlay
  └── headlamp-oidc-secret.yaml         # Encrypted OIDC client secret (SOPS)

apps/home/kustomization.yaml            # Updated to include Headlamp
```

## Secrets Encryption

All secrets are encrypted using SOPS with PGP:

- `authelia-secrets.yaml`: JWT, session, storage encryption, OIDC keys
- `users-database.yaml`: User credentials (password hashes)
- `headlamp-oidc-secret.yaml`: OIDC client configuration

Flux will automatically decrypt these using the `sops-gpg` secret in the cluster.

## Adding More Users

To add more users, update `infrastructure/authelia/users-database.yaml`:

1. Decrypt the file:

   ```bash
   sops infrastructure/authelia/users-database.yaml
   ```

2. Generate a password hash:

   ```bash
   docker run --rm authelia/authelia:latest \
     authelia crypto hash generate argon2 \
     --password 'YourPassword' --config /dev/null
   ```

3. Add the new user to the YAML under `users:`:

   ```yaml
   users:
     admin:
       # ... existing admin user
     newuser:
       displayname: "New User"
       password: "$argon2id$v=19$m=65536,t=3,p=4$..."  # Your generated hash
       email: newuser@home.local
       groups:
         - developers  # or admins for full access
   ```

4. Save (SOPS will auto-encrypt) and commit

## Monitoring Deployment

Watch Flux reconcile the new resources:

```bash
make watch
```

Check specific resources:

```bash
# Authelia
kubectl get helmrelease -n authelia
kubectl get pods -n authelia
kubectl get ingress -n authelia
kubectl get certificate -n authelia

# Headlamp
kubectl get helmrelease -n headlamp
kubectl get pods -n headlamp
kubectl get ingress -n headlamp
kubectl get certificate -n headlamp
```

## Troubleshooting

### DNS not resolving

- Check external-dns logs: `kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`
- Verify Cloudflare API token is valid
- Check ingress annotations are correct

### Certificate not issuing

- Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
- Verify cert-manager ClusterIssuer exists: `kubectl get clusterissuer`
- Check certificate status: `kubectl describe certificate -n authelia authelia-tls-secret`

### Authelia pod not starting

- Check logs: `kubectl logs -n authelia -l app.kubernetes.io/name=authelia`
- Verify secrets exist: `kubectl get secret -n authelia authelia-secrets`
- Check users database: `kubectl get secret -n authelia authelia-users-database`

### Headlamp OIDC not working

- Verify callback URL matches: `https://headlamp.home.lewelly.com/oidc-callback`
- Check Authelia client configuration in Authelia logs
- Review Authelia logs: `kubectl logs -n authelia -l app.kubernetes.io/name=authelia`
- Verify secret exists: `kubectl get secret -n headlamp headlamp-oidc-secret`

### 2FA setup issues

- If you lose your 2FA device, you'll need to reset the user in the database
- The 2FA secrets are stored in Authelia's SQLite database on the PVC

## Next Steps

1. **Commit and push** these changes to trigger Flux deployment
2. **Wait for DNS** propagation (usually 1-2 minutes)
3. **Wait for certificates** to be issued (can take 2-5 minutes)
4. **Test authentication** flow
5. **Change default password** and configure additional users as needed
6. **Set up 2FA** on first login (required for security)

## Security Notes

- All traffic is encrypted with TLS (Let's Encrypt certificates)
- OIDC tokens are used for authentication
- TOTP 2FA is enabled by default (required on first login)
- Passwords are hashed with Argon2id
- All secrets are encrypted at rest with SOPS
- RBAC is enforced based on group membership
- Session cookies are httpOnly and secure

## K9s Local Access

You mentioned you already have K9s set up locally. K9s will continue to work with your existing kubeconfig and doesn't require OIDC integration.

---

**Generated on**: $(date)
**Deployed by**: Claude Code
