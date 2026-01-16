# JWT Authentication for Scopes

This directory manages JWT-based authentication for scopes with "exposer" visibility using Istio security resources.

## Overview

The JWT authentication flow uses two Istio Custom Resource Definitions (CRDs):

1. **RequestAuthentication**: Validates JWT tokens from incoming requests
2. **AuthorizationPolicy**: Enforces access control based on JWT claims

## Important: Istio Gateway Dependency

**This authentication mechanism ONLY works with Istio gateways.** The resources use Istio-specific CRDs (`security.istio.io/v1`) that are processed by Istio's data plane (Envoy proxy). If your gateway is not Istio-based (e.g., Nginx, Kong, Traefik), you will need to implement authentication using that gateway's native mechanisms.

## Resources Provisioned

### 1. RequestAuthentication

Created once per cluster in the gateway namespace. This resource configures JWT validation.

**File**: [templates/request-authentication.yaml.tmpl](templates/request-authentication.yaml.tmpl)

**Example**:
```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: nullplatform-scope-jwt-auth
  namespace: gateways
spec:
  selector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: my-gateway
  jwtRules:
  - issuer: "https://api.nullplatform.com/scope"
    jwksUri: "https://api.nullplatform.com/scope/.well-known/jwks.json"
    fromHeaders:
    - name: Authorization
      prefix: "Bearer "
    fromCookies:
    - "np_scope_token"
    outputClaimToHeaders:
    - header: "X-User-ID"
      claim: "sub"
    - header: "X-User-Email"
      claim: "email"
```

**Key Features**:
- Validates JWTs from `Authorization: Bearer <token>` header or `np_scope_token` cookie
- Extracts claims and forwards them as headers to backend services
- Non-blocking: Invalid tokens are marked but not rejected at this stage

### 2. AuthorizationPolicy

Created per scope domain. This resource enforces JWT requirements.

**File**: [templates/authorization-policy.yaml.tmpl](templates/authorization-policy.yaml.tmpl)

**Example**:
```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt-scope-123
  namespace: gateways
spec:
  action: DENY
  selector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: my-gateway
  rules:
  - to:
    - operation:
        hosts:
        - "my-app.example.com"
        ports: ["443"]
        notPaths:
        - /health
        - /ready
        - /metrics
    when:
    - key: request.auth.claims[aud]
      notValues: ["my-app.example.com"]
```

**Key Features**:
- DENY action: Blocks requests that don't meet the conditions
- Requires JWT audience (`aud` claim) to match the scope domain
- Exempts health check endpoints (`/health`, `/ready`, `/metrics`)
- Applies only to HTTPS traffic (port 443)

## Flow Diagram

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ Request with JWT
       │ (Header or Cookie)
       ▼
┌─────────────────────┐
│  Istio Gateway      │
│  (Envoy Proxy)      │
└──────┬──────────────┘
       │
       ▼
┌──────────────────────────────┐
│  RequestAuthentication       │
│  - Validates JWT signature   │
│  - Checks issuer/expiration  │
│  - Extracts claims           │
└──────┬───────────────────────┘
       │
       ▼
┌──────────────────────────────┐
│  AuthorizationPolicy         │
│  - Checks aud claim matches  │
│  - DENY if invalid/missing   │
└──────┬───────────────────────┘
       │
       ▼ (if authorized)
┌─────────────────────┐
│  Backend Service    │
│  + Headers:         │
│    X-User-ID        │
│    X-User-Email     │
└─────────────────────┘
```

## Script Usage

The [manage_jwt_auth](manage_jwt_auth) script handles resource lifecycle:

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_AUTHORIZATION_ENABLED` | - | Set to "true" to enable JWT auth |
| `ACTION` | "create" | Action to perform: "create", "apply", or "delete" |
| `GATEWAY_NAMESPACE` | "gateways" | Namespace where gateway resources exist |
| `JWT_ISSUER` | `https://api.nullplatform.com/scope` | JWT issuer URL |
| `JWT_JWKS_URI` | `https://api.nullplatform.com/scope/.well-known/jwks.json` | JWKS endpoint for key verification |
| `SCOPE_ID` | - | Unique scope identifier |
| `SCOPE_DOMAIN` | - | Domain for the scope (e.g., `app.example.com`) |
| `GATEWAY_NAME` | - | Name of the Istio gateway |

### Create Resources

```bash
export JWT_AUTHORIZATION_ENABLED=true
export SCOPE_ID=my_scope_123
export SCOPE_DOMAIN=my-app.example.com
export GATEWAY_NAME=my-gateway
export ACTION=create

./manage_jwt_auth
```

### Delete Authorization Policy

```bash
export JWT_AUTHORIZATION_ENABLED=true
export SCOPE_ID=my_scope_123
export ACTION=delete

./manage_jwt_auth
```

## JWT Token Requirements

Valid JWT tokens must include:

- **`iss` (issuer)**: Must match `JWT_ISSUER` (default: `https://api.nullplatform.com/scope`)
- **`aud` (audience)**: Must match the scope domain (e.g., `my-app.example.com`)
- **`sub` (subject)**: User identifier
- **`email`**: User email
- **`exp` (expiration)**: Token must not be expired

## Token Sources

The RequestAuthentication accepts tokens from:

1. **Authorization Header**: `Authorization: Bearer <token>`
2. **Cookie**: `np_scope_token=<token>`

This allows both API clients (using headers) and browsers (using cookies) to authenticate.

## Exempted Paths

The following paths are exempted from JWT validation to support infrastructure monitoring:

- `/health` - Health check endpoint
- `/ready` - Readiness probe endpoint
- `/metrics` - Metrics collection endpoint

## Troubleshooting

### Request Rejected with 403

**Symptom**: Requests to your domain return 403 Forbidden.

**Possible Causes**:
1. Missing or invalid JWT token
2. Token `aud` claim doesn't match the domain
3. Token expired or signature invalid
4. Token issuer doesn't match configuration

**Debug Steps**:
```bash
# Check RequestAuthentication exists
kubectl get requestauthentication -n gateways

# Check AuthorizationPolicy exists for your scope
kubectl get authorizationpolicy -n gateways | grep require-jwt

# View AuthorizationPolicy details
kubectl describe authorizationpolicy require-jwt-<scope-id> -n gateways

# Check Istio proxy logs
kubectl logs -n gateways <gateway-pod-name> -c istio-proxy
```

### Token Validation Fails

**Symptom**: Logs show JWT validation errors.

**Check**:
```bash
# Verify JWKS URI is accessible
curl https://api.nullplatform.com/scope/.well-known/jwks.json

# Decode your JWT to check claims (use jwt.io)
# Verify:
# - iss matches JWT_ISSUER
# - aud matches SCOPE_DOMAIN
# - exp is in the future
```

### RequestAuthentication Not Applied

**Symptom**: JWT validation doesn't occur.

**Check**:
```bash
# Verify gateway has the correct label
kubectl get gateway -n gateways -o yaml | grep gateway-name

# Verify RequestAuthentication selector matches
kubectl get requestauthentication nullplatform-scope-jwt-auth -n gateways -o yaml
```

## Alternatives for Non-Istio Gateways

If you cannot use Istio, consider these alternatives:

- **Nginx Ingress Controller**: Use `auth-url` annotation with external auth service
- **Kong Gateway**: Use Kong JWT plugin
- **Traefik**: Use ForwardAuth middleware
- **AWS ALB**: Use AWS Cognito User Pools or Lambda authorizers
- **Application-level**: Implement JWT validation in your application code

## References

- [Istio RequestAuthentication Documentation](https://istio.io/latest/docs/reference/config/security/request_authentication/)
- [Istio AuthorizationPolicy Documentation](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- [JWT Best Practices](https://datatracker.ietf.org/doc/html/rfc8725)
