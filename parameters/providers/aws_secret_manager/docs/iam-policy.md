# IAM Policy — Least Privilege

This document specifies the minimum IAM permissions required to operate the `parameters/providers/aws_secret_manager/` provider. The policy is scoped to the `parameters/*` namespace and avoids account-wide wildcards.

---

## Wildcards: which ones are OK

There are two distinct uses of `*` in IAM, frequently conflated:

| Pattern                                              | Meaning                              | Allowed here? |
|------------------------------------------------------|--------------------------------------|---------------|
| `"Resource": "*"`                                    | All resources of all types in the account | **No**        |
| `"Resource": "arn:...:secret:parameters/*"`          | Path glob on the `parameters/` prefix     | **Yes**       |

The second is not a privilege escalation — it is the only way to express "all secrets owned by this provider" given that secret names are UUIDs generated at runtime and cannot be enumerated in advance. Avoiding it would force either explicit per-secret policies (impossible for unknown UUIDs) or `Resource: "*"` (much wider).

---

## Required actions

| Action                            | Used by    | Why                                                                  |
|-----------------------------------|------------|----------------------------------------------------------------------|
| `secretsmanager:CreateSecret`     | `store`    | Creates the secret with the JSON envelope                            |
| `secretsmanager:GetSecretValue`   | `retrieve` | Reads the JSON envelope back                                         |
| `secretsmanager:DeleteSecret`     | `delete`   | Removes the secret (with `--force-delete-without-recovery`)          |
| `secretsmanager:DescribeSecret`   | optional   | Useful for diagnostics; not strictly required by the current scripts |

`UpdateSecret`, `PutSecretValue`, `RestoreSecret`, `TagResource`, `RotateSecret` are **not** required and should not be granted unless the scripts grow to use them.

---

## Recommended policy

Replace placeholders before applying:

- `<AWS_REGION>` — region where the provider stores secrets (e.g. `us-east-1`).
- `<AWS_ACCOUNT_ID>` — 12-digit AWS account id of the agent.
- `<KMS_KEY_ID>` — only if using a customer-managed KMS key (see KMS section below). Otherwise omit the entire KMS statement.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageNullplatformSecretParameters",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DeleteSecret",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:parameters/*"
      ]
    }
  ]
}
```

### Why this is sufficient

- Confined to a single region and account.
- Confined to the `parameters/` name prefix — no other secrets in the account are reachable.
- No `Resource: "*"`.
- No write actions beyond create + delete (no overwrite, no rotation).
- No tagging or policy-management actions.

---

## Splitting agent vs consumer

The policy above grants both write and read in one role. In production it is often cleaner to split them:

### Agent role (executes the workflow scripts)

Needs `CreateSecret`, `GetSecretValue`, `DeleteSecret`, `DescribeSecret`. Same as the recommended policy above.

### Consumer role (the application that needs the value at runtime)

Needs only `GetSecretValue` (and `DescribeSecret` if the consumer enumerates metadata):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadNullplatformSecretParameters",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:parameters/*"
      ]
    }
  ]
}
```

If a consumer should only read **specific** secrets (rather than every parameter in the namespace), narrow the resource list:

```json
"Resource": [
  "arn:aws:secretsmanager:<AWS_REGION>:<AWS_ACCOUNT_ID>:secret:parameters/<EXTERNAL_ID>-*"
]
```

The trailing `-*` is required because AWS SM appends a 6-character suffix to the ARN of every secret it creates (see `architecture.md`). Omitting it makes the ARN never match.

---

## KMS (only if using a customer-managed key)

If you pass `--kms-key-id` to `CreateSecret` (i.e. you do not want to use the default `aws/secretsmanager` AWS-managed key), both the agent and any consumer also need access to the CMK. Add this statement to **both** the agent and consumer policies:

```json
{
  "Sid": "UseCustomerManagedKmsKey",
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": [
    "arn:aws:kms:<AWS_REGION>:<AWS_ACCOUNT_ID>:key/<KMS_KEY_ID>"
  ],
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "secretsmanager.<AWS_REGION>.amazonaws.com"
    }
  }
}
```

The `kms:ViaService` condition is the security-relevant part: it ensures the role can only use the key **through Secrets Manager**, not for arbitrary `kms:Decrypt` calls against other ciphertexts encrypted with the same key.

The CMK's **key policy** must also allow the role principal — IAM permissions alone are not enough for KMS. Configure that on the key, not on the role.

---

## Conditions worth adding

Optional hardening, depending on threat model:

### Restrict to specific VPC endpoints

If the agent runs inside a VPC with a Secrets Manager interface endpoint:

```json
"Condition": {
  "StringEquals": {
    "aws:SourceVpce": "<VPCE_ID>"
  }
}
```

### Restrict to a specific source IAM role

For consumers running in a known service account (IRSA) or instance profile:

```json
"Condition": {
  "ArnEquals": {
    "aws:PrincipalArn": "arn:aws:iam::<AWS_ACCOUNT_ID>:role/<ROLE_NAME>"
  }
}
```

(This is more typically enforced via the trust policy of the role itself, but resource policies on the secret can pin it as defense-in-depth.)

### Enforce TLS

Mostly handled by AWS by default, but explicitly denying non-TLS traffic is cheap insurance:

```json
"Condition": {
  "Bool": {
    "aws:SecureTransport": "true"
  }
}
```

---

## What not to grant

For reference — these are commonly requested but **not** needed by the current scripts and should be denied unless a specific use case is documented:

- `secretsmanager:PutSecretValue` — would let the agent overwrite values. Not used; secrets are immutable in this design.
- `secretsmanager:UpdateSecret` — same reasoning.
- `secretsmanager:RotateSecret` — rotation is not implemented.
- `secretsmanager:TagResource`, `UntagResource` — no tagging in current scripts.
- `secretsmanager:PutResourcePolicy` — would let the agent change cross-account access. Should be reserved for a separate admin role.
- `secretsmanager:ReplicateSecretToRegions` — replication is opt-in and out of scope.
- `iam:*` of any kind — this provider does not manage IAM.
