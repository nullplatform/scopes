# IAM Policy — Parameter Store Provider, Least Privilege

Minimum IAM permissions required to operate the `parameters/providers/parameter_store/` provider, scoped to the configured `PS_NAME_PREFIX`.

---

## Required actions

| Action                       | Used by    | Why                                                    |
|------------------------------|------------|--------------------------------------------------------|
| `ssm:PutParameter`           | `store`    | Creates the parameter (String or SecureString)         |
| `ssm:GetParameter`           | `retrieve` | Reads the value back                                   |
| `ssm:DeleteParameter`        | `delete`   | Removes the parameter                                  |
| `ssm:DescribeParameters`     | optional   | Useful for diagnostics                                 |

`PutParameterBatch`, `LabelParameterVersion`, `GetParameterHistory`, `AddTagsToResource` are **not** required and should not be granted unless code grows to use them.

---

## Recommended policy

Replace placeholders before applying:

- `<AWS_REGION>` — region where parameters are stored.
- `<AWS_ACCOUNT_ID>` — 12-digit AWS account id.
- `<PS_NAME_PREFIX>` — the configured prefix (e.g. `nullplatform/parameters`). Strip leading and trailing `/` when placing into the ARN.
- `<KMS_KEY_ID>` — required if you store any `SecureString` (kind=secret). For default `alias/aws/ssm` you can omit the KMS statement.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageNullplatformParameters",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter",
        "ssm:DescribeParameters"
      ],
      "Resource": [
        "arn:aws:ssm:<AWS_REGION>:<AWS_ACCOUNT_ID>:parameter/<PS_NAME_PREFIX>/*"
      ]
    }
  ]
}
```

Note the ARN format: `parameter/<prefix>/*` — no extra slash between `parameter` and the prefix because the prefix itself starts with `/`. So if `PS_NAME_PREFIX=/nullplatform/parameters/`, the ARN is `arn:aws:ssm:...:parameter/nullplatform/parameters/*`.

---

## KMS (only when storing SecureString with a CMK)

If `PS_KMS_KEY_ID` is set to a customer-managed key, both the agent (writer) and any consumer (reader) need KMS permissions. Add this to both policies:

```json
{
  "Sid": "UseCustomerManagedKmsKeyForParameterStore",
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": [
    "arn:aws:kms:<AWS_REGION>:<AWS_ACCOUNT_ID>:key/<KMS_KEY_ID>"
  ],
  "Condition": {
    "StringEquals": {
      "kms:ViaService": "ssm.<AWS_REGION>.amazonaws.com"
    }
  }
}
```

The `kms:ViaService` condition restricts the key to SSM use — without it, the role could decrypt arbitrary ciphertexts encrypted with the same key. The CMK's **key policy** must also allow the role principal; IAM permissions alone aren't enough for KMS.

If you use the default `alias/aws/ssm` (AWS-managed), no extra KMS statement is needed — Parameter Store handles encryption transparently.

---

## Splitting agent vs consumer

The writer (this provider's scripts) needs put + get + delete. A runtime consumer typically only needs read:

```json
{
  "Sid": "ReadNullplatformParameters",
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameter",
    "ssm:GetParameters",
    "ssm:GetParametersByPath"
  ],
  "Resource": [
    "arn:aws:ssm:<AWS_REGION>:<AWS_ACCOUNT_ID>:parameter/<PS_NAME_PREFIX>/*"
  ]
}
```

`GetParametersByPath` is useful if a consumer wants to enumerate all parameters under a hierarchical prefix (e.g. fetching all secrets for an app in one call).

---

## What not to grant

- `ssm:*` (account-wide) — opens access to OS commands (`AWS-RunShellScript`), maintenance windows, session manager, etc.
- `ssm:PutParameter` with `Resource: "*"` — lets the role write to ANY parameter in the account (including other apps' secrets).
- `ssm:LabelParameterVersion`, `ssm:UnlabelParameterVersion` — versioning workflows; not used by this provider.
- `iam:*` — this provider doesn't manage IAM.
