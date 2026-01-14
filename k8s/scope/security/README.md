# JWT Authentication for Scopes

This directory contains scripts and templates for managing JWT authentication on scopes with `exposer` visibility.

## Overview

When a scope is created with `visibility: exposer`, the workflow automatically provisions JWT authentication resources in the Istio gateway namespace:

1. **RequestAuthentication** - Validates JWT tokens from nullplatform scope API (one per cluster)
2. **AuthorizationPolicy** - Enforces JWT requirement per scope domain

## How it Works

### Create/Update Workflow

1. The `manage_jwt_auth` script checks if `SCOPE_VISIBILITY` is "exposer"
2. If yes:
   - Checks if `RequestAuthentication` exists globally (one per cluster)
   - Creates it if it doesn't exist
   - Creates/updates an `AuthorizationPolicy` specific to the scope's domain

### Delete Workflow

1. Deletes the scope-specific `AuthorizationPolicy`
2. Leaves the global `RequestAuthentication` intact (shared by all scopes)

## Configuration

The following environment variables are used:

- `SCOPE_VISIBILITY` - Must be "exposer" to enable JWT auth
- `SCOPE_DOMAIN` - The domain to protect (e.g., `app.example.com`)
- `GATEWAY_NAME` - The Istio gateway name (e.g., `gateway-public`)
- `GATEWAY_NAMESPACE` - Namespace where gateway resources live (default: `gateways`)
- `JWT_ISSUER` - JWT issuer URL (default: `https://api.nullplatform.com/scope`)
- `JWT_JWKS_URI` - JWKS endpoint (default: `https://api.nullplatform.com/scope/.well-known/jwks.json`)

## Resources Created

### RequestAuthentication: `nullplatform-scope-jwt-auth`

- **Location**: `gateways` namespace
- **Scope**: Cluster-wide (one instance)
- **Function**: Validates JWT signature and extracts claims
- **Behavior**: Does not enforce authentication (that's done by AuthorizationPolicy)

### AuthorizationPolicy: `require-jwt-{scope-id}`

- **Location**: `gateways` namespace
- **Scope**: Per scope domain
- **Function**: Denies access without valid JWT
- **Action**: DENY
- **Applies to**: Specific scope domain only
- **Exceptions**: Health endpoints (`/health`, `/ready`, `/metrics`)

## JWT Token Requirements

Tokens must:
- Be signed by `https://api.nullplatform.com/scope`
- Have valid signature (verified against JWKS)
- Include `iss` claim matching the issuer
- Include `aud` claim matching the target domain
- Not be expired

## Token Sources

The system accepts JWT tokens from:
1. `Authorization` header with `Bearer ` prefix
2. `np_scope_token` cookie

## Extracted Claims

The following JWT claims are extracted to HTTP headers:
- `sub` → `X-User-ID`
- `email` → `X-User-Email`
- `scope` → `X-User-Scopes`

## Example

For a scope with:
- ID: `playground-floppy-bird-api-production-kjstb`
- Domain: `playground-floppy-bird-api-production-kjstb.edenred.nullimplementation.com`
- Visibility: `exposer`

The workflow creates:
1. `RequestAuthentication/nullplatform-scope-jwt-auth` (if not exists)
2. `AuthorizationPolicy/require-jwt-playground-floppy-bird-api-production-kjstb`

Access behavior:
- ✅ Requests with valid JWT → Allowed
- ❌ Requests without JWT → 403 RBAC Denied
- ✅ Health endpoints → Always allowed

## Files

```
scope/security/
├── README.md                                      # This file
├── manage_jwt_auth                                # Main script
└── templates/
    ├── request-authentication.yaml.tmpl           # RequestAuthentication template
    └── authorization-policy.yaml.tmpl             # AuthorizationPolicy template
```

## Troubleshooting

### JWT validation failing

Check that:
1. Token is not expired
2. Token `aud` claim matches the domain being accessed
3. Token `iss` claim is `https://api.nullplatform.com/scope`
4. JWKS endpoint is accessible from the cluster

### AuthorizationPolicy not working

Verify:
1. Scope visibility is "exposer"
2. AuthorizationPolicy exists: `kubectl get authorizationpolicy -n gateways`
3. Policy selector matches gateway pods
4. Check Envoy logs: `kubectl logs -n gateways <gateway-pod> -f`

### RequestAuthentication not created

Check:
1. Template files exist in `scope/security/templates/`
2. Gomplate is installed and working
3. kubectl has permissions to create resources in gateways namespace
