# Image pull secrets across namespaces

Kubernetes only resolves `imagePullSecrets` inside the pod's own namespace. With the default `K8S_NAMESPACE_STRATEGY=static` every scope deploys to `K8S_NAMESPACE`, where the registry credentials already live. With `np_namespace` or `np_account_namespace`, workloads run in one namespace per nullplatform namespace, so the credentials have to exist there too.

## What the scope does

On every deployment, `deployment/build_context` copies each secret listed in `IMAGE_PULL_SECRETS` from the source namespace into the namespace the scope deploys to:

- The copy drops server-owned metadata (`uid`, `resourceVersion`, `managedFields`, `ownerReferences`, the `last-applied-configuration` annotation) and gets the label `nullplatform.com/synced-from=<source namespace>`.
- It is re-applied on every deploy, so a rotated source credential reaches the copies on the next deploy.
- A secret missing in the source namespace is skipped with a warning. This is the normal case on clusters where nodes pull with IAM (EKS + ECR in the same account, AKS + ACR attached, GKE + Artifact Registry): the pod references the secret name but the kubelet does not need it.
- Nothing happens when the source and target namespaces are the same (`static` strategy, or legacy scopes that stay in `K8S_NAMESPACE`).

## Configuration

| Key | Provider path (`scope-configurations`) | Default | Description |
|---|---|---|---|
| `IMAGE_PULL_SECRETS_SYNC` | `security.image_pull_secrets_sync` | `true` | Set to `false` when an external controller keeps the copies in sync. |
| `PULL_SECRET_SOURCE_NAMESPACE` | `security.pull_secret_source_namespace` | `K8S_NAMESPACE` | Namespace that holds the credentials to copy. |

## Expiring credentials (ECR tokens)

Static credentials (a private Docker registry user and password, a GitLab deploy token, an Artifactory API key) are fully covered by the copy on each deploy.

ECR authorization tokens expire every 12 hours. The copy is only refreshed when the scope deploys, so between deploys it goes stale, and a pod rescheduled on a node that has not cached the image fails with `ImagePullBackOff`. The scope logs a warning when it copies a secret whose registry is an ECR host. Two options:

1. **Pull with IAM (recommended).** Give the node role (or the pod's IRSA / Pod Identity role) `ecr:GetAuthorizationToken`, `ecr:BatchGetImage` and `ecr:GetDownloadUrlForLayer`. No pull secret is needed at all.
2. **Keep the copies in sync continuously.** Whatever refreshes the source secret keeps writing only to the source namespace; a controller clones it into every nullplatform-owned namespace on each change. With [Kyverno](https://kyverno.io/):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: nullplatform-sync-pull-secrets
spec:
  generateExisting: true
  rules:
    - name: clone-registry-credentials
      match:
        any:
          - resources:
              kinds: ["Namespace"]
              selector:
                matchExpressions:
                  - {key: nullplatform, operator: In, values: ["true"]}
                  - {key: namespace_id, operator: Exists}
      generate:
        apiVersion: v1
        kind: Secret
        name: ecr-secret
        namespace: "{{request.object.metadata.name}}"
        synchronize: true
        clone:
          namespace: nullplatform
          name: ecr-secret
```

Set `IMAGE_PULL_SECRETS_SYNC=false` when using this policy so the scope and Kyverno do not both manage the same secret.
