# AWS Systems Manager Parameter Store — Provider Architecture

This document describes the `parameters/providers/parameter_store/` implementation. It stores nullplatform parameters in AWS SSM Parameter Store, using `String` for plain parameters and `SecureString` (KMS-encrypted) for secrets.

Cheapest provider in the package — Standard tier is free up to 10,000 parameters.

---

## Lifecycle

| Step | What happens                                                                |
|------|-----------------------------------------------------------------------------|
| `setup`     | Reads `AWS_REGION`, `PS_NAME_PREFIX` (default `/nullplatform/`), `PS_KMS_KEY_ID`, `PS_TIER`. Normalizes prefix to start/end with `/`. |
| `store`     | Composes path via `build_external_id`. Calls `aws ssm put-parameter --overwrite`. Captures `.Version` from response. Returns `external_id = <path>#<version>`. |
| `retrieve`  | Parses path + version. Calls `aws ssm get-parameter --with-decryption`. If a version is present in external_id, appends `:<N>` to target that specific version. |
| `delete`    | Calls `aws ssm delete-parameter`. Idempotent (suppresses `ParameterNotFound`). |
| `notify`    | Not implemented — dispatcher returns default `{success: true}`. |

---

## Storage layout

Every parameter name is composed by `parameters/utils/build_external_id`:

```
<PS_NAME_PREFIX><entity_type>=<slug>-<id>/.../<dim_key>=<dim_value>/<parameter_name>-<parameter_id>
```

Default `PS_NAME_PREFIX` is `/nullplatform/`. SSM requires names to start with `/` for hierarchical organization.

Example:

```
/nullplatform/organization=acme-1255165411/account=prod-95118862/.../DB_PASSWORD-42
```

IAM can target the hierarchy via ARN pattern `arn:aws:ssm:<region>:<account>:parameter/nullplatform/*`.

---

## Type selection via PARAMETER_KIND

This is the only provider in the package that branches on `PARAMETER_KIND`:

| Kind        | SSM Type        | KMS                                                  |
|-------------|-----------------|------------------------------------------------------|
| `parameter` | `String`        | None (plain text)                                    |
| `secret`    | `SecureString`  | `PS_KMS_KEY_ID` if set, otherwise `alias/aws/ssm`    |

For other providers in the package, kind is informational — their backends encrypt all values uniformly.

---

## Versioning

Parameter Store retains versions automatically. `put-parameter --overwrite` creates a new version on every call.

### Version identity in external_id

The `external_id` returned by `store` encodes both the path and the version:

```
<canonical_path>#<version_id>
```

For Parameter Store, `version_id` is **the literal integer `.Version` returned by `put-parameter`** — we do not invent or normalize it. AWS returns it; we copy it verbatim. Real example:

```
organization=acme-1255165411/.../DB_PASSWORD-42#7
```

Here `7` means "the 7th version of this parameter". SSM addresses historical versions by suffixing the parameter name with `:<N>`, so on retrieve we call `get-parameter --name "<full-path>:7"`.

On `retrieve`:
- With `#<N>` → fetch version N.
- Without → fetch latest.

On `delete`, the version suffix is ignored — `delete-parameter` removes all versions.

---

## Tiers

| Tier                  | Free                  | Value size  | Use case                          |
|-----------------------|-----------------------|-------------|-----------------------------------|
| `Standard` (default)  | up to 10,000 params   | 4 KB        | Most cases                        |
| `Advanced`            | $0.05/param/month     | 8 KB        | Large values or > 10k params      |
| `Intelligent-Tiering` | Auto-promotes         | varies      | Mixed sizes                       |

Switch tiers via provider config `tier` attribute.

---

## Configuration

`PROVIDER_CONFIG` shape:

```json
{
  "region":      "us-east-1",
  "name_prefix": "/nullplatform/",
  "kms_key_id":  "alias/parameters-secure",
  "tier":        "Standard"
}
```

`kms_key_id` only matters for `kind=secret` (SecureString). For `kind=parameter` (String) it's ignored.
