# Kubernetes Scope Configuration

Este documento describe todas las variables de configuración disponibles para scopes de Kubernetes, su jerarquía de prioridades y cómo configurarlas.

## Jerarquía de Configuración

Las variables de configuración siguen una jerarquía de prioridades:

```
1. Variable de entorno (ENV VAR) - Máxima prioridad
   ↓
2. Provider scope-configuration - Configuración específica del scope
   ↓
3. Providers existentes - container-orchestration / cloud-providers
   ↓
4. values.yaml - Valores por defecto del scope tipo
```

## Variables de Configuración

### Scope Context (`k8s/scope/build_context`)

Variables que definen el contexto general del scope y recursos de Kubernetes.

| Variable | Descripción | values.yaml | scope-configuration (JSON Schema) | Archivos que la usan | Default |
|----------|-------------|-------------|-----------------------------------|---------------------|---------|
| **K8S_NAMESPACE** | Namespace de Kubernetes donde se despliegan los recursos | `configuration.K8S_NAMESPACE` | `kubernetes.namespace` | `k8s/scope/build_context`<br>`k8s/deployment/build_context` | `"nullplatform"` |
| **CREATE_K8S_NAMESPACE_IF_NOT_EXIST** | Si se debe crear el namespace si no existe | `configuration.CREATE_K8S_NAMESPACE_IF_NOT_EXIST` | `kubernetes.create_namespace_if_not_exist` | `k8s/scope/build_context` | `"true"` |
| **K8S_MODIFIERS** | Modificadores (annotations, labels, tolerations) para recursos K8s | `configuration.K8S_MODIFIERS` | `kubernetes.modifiers` | `k8s/scope/build_context` | `{}` |
| **REGION** | Región de AWS/Cloud donde se despliegan los recursos | N/A (calculado) | `region` | `k8s/scope/build_context` | `"us-east-1"` |
| **USE_ACCOUNT_SLUG** | Si se debe usar el slug de account como dominio de aplicación | `configuration.USE_ACCOUNT_SLUG` | `networking.application_domain` | `k8s/scope/build_context` | `"false"` |
| **DOMAIN** | Dominio público para la aplicación | `configuration.DOMAIN` | `networking.domain_name` | `k8s/scope/build_context` | `"nullapps.io"` |
| **PRIVATE_DOMAIN** | Dominio privado para servicios internos | `configuration.PRIVATE_DOMAIN` | `networking.private_domain_name` | `k8s/scope/build_context` | `"nullapps.io"` |
| **PUBLIC_GATEWAY_NAME** | Nombre del gateway público para ingress | Env var o default | `gateway.public_name` | `k8s/scope/build_context` | `"gateway-public"` |
| **PRIVATE_GATEWAY_NAME** | Nombre del gateway privado/interno para ingress | Env var o default | `gateway.private_name` | `k8s/scope/build_context` | `"gateway-internal"` |
| **ALB_NAME** (public) | Nombre del Application Load Balancer público | Calculado | `balancer.public_name` | `k8s/scope/build_context` | `"k8s-nullplatform-internet-facing"` |
| **ALB_NAME** (private) | Nombre del Application Load Balancer privado | Calculado | `balancer.private_name` | `k8s/scope/build_context` | `"k8s-nullplatform-internal"` |
| **DNS_TYPE** | Tipo de DNS provider (route53, azure, external_dns) | `configuration.DNS_TYPE` | `dns.type` | `k8s/scope/build_context`<br>Workflows DNS | `"route53"` |
| **ALB_RECONCILIATION_ENABLED** | Si está habilitada la reconciliación de ALB | `configuration.ALB_RECONCILIATION_ENABLED` | `networking.alb_reconciliation_enabled` | `k8s/scope/build_context`<br>Workflows balancer | `"false"` |
| **DEPLOYMENT_MAX_WAIT_IN_SECONDS** | Tiempo máximo de espera para deployments (segundos) | `configuration.DEPLOYMENT_MAX_WAIT_IN_SECONDS` | `deployment.max_wait_seconds` | `k8s/scope/build_context`<br>Workflows deployment | `600` |
| **MANIFEST_BACKUP** | Configuración de backup de manifiestos K8s | `configuration.MANIFEST_BACKUP` | `manifest_backup` | `k8s/scope/build_context`<br>Workflows backup | `{}` |
| **VAULT_ADDR** | URL del servidor Vault para secrets | `configuration.VAULT_ADDR` | `vault.address` | `k8s/scope/build_context`<br>Workflows secrets | `""` (vacío) |
| **VAULT_TOKEN** | Token de autenticación para Vault | `configuration.VAULT_TOKEN` | `vault.token` | `k8s/scope/build_context`<br>Workflows secrets | `""` (vacío) |

### Deployment Context (`k8s/deployment/build_context`)

Variables específicas del deployment y configuración de pods.

| Variable | Descripción | values.yaml | scope-configuration (JSON Schema) | Archivos que la usan | Default |
|----------|-------------|-------------|-----------------------------------|---------------------|---------|
| **IMAGE_PULL_SECRETS** | Secrets para descargar imágenes de registries privados | `configuration.IMAGE_PULL_SECRETS` | `deployment.image_pull_secrets` | `k8s/deployment/build_context` | `{}` |
| **TRAFFIC_CONTAINER_IMAGE** | Imagen del contenedor sidecar traffic manager | `configuration.TRAFFIC_CONTAINER_IMAGE` | `deployment.traffic_container_image` | `k8s/deployment/build_context` | `"public.ecr.aws/nullplatform/k8s-traffic-manager:latest"` |
| **POD_DISRUPTION_BUDGET_ENABLED** | Si está habilitado el Pod Disruption Budget | `configuration.POD_DISRUPTION_BUDGET.ENABLED` | `deployment.pod_disruption_budget.enabled` | `k8s/deployment/build_context` | `"false"` |
| **POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE** | Máximo número o porcentaje de pods que pueden estar no disponibles | `configuration.POD_DISRUPTION_BUDGET.MAX_UNAVAILABLE` | `deployment.pod_disruption_budget.max_unavailable` | `k8s/deployment/build_context` | `"25%"` |
| **TRAFFIC_MANAGER_CONFIG_MAP** | Nombre del ConfigMap con configuración custom de traffic manager | `configuration.TRAFFIC_MANAGER_CONFIG_MAP` | `deployment.traffic_manager_config_map` | `k8s/deployment/build_context` | `""` (vacío) |
| **DEPLOY_STRATEGY** | Estrategia de deployment (rolling o blue-green) | `configuration.DEPLOY_STRATEGY` | `deployment.strategy` | `k8s/deployment/build_context`<br>`k8s/deployment/scale_deployments` | `"rolling"` |
| **IAM** | Configuración de IAM roles y policies para service accounts | `configuration.IAM` | `deployment.iam` | `k8s/deployment/build_context`<br>`k8s/scope/iam/*` | `{}` |

## Configuración mediante scope-configuration Provider

### Estructura JSON Completa

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production",
      "create_namespace_if_not_exist": "true",
      "modifiers": {
        "global": {
          "annotations": {
            "prometheus.io/scrape": "true"
          },
          "labels": {
            "environment": "production"
          }
        },
        "deployment": {
          "tolerations": [
            {
              "key": "dedicated",
              "operator": "Equal",
              "value": "production",
              "effect": "NoSchedule"
            }
          ]
        }
      }
    },
    "region": "us-west-2",
    "networking": {
      "domain_name": "example.com",
      "private_domain_name": "internal.example.com",
      "application_domain": "false"
    },
    "gateway": {
      "public_name": "my-public-gateway",
      "private_name": "my-private-gateway"
    },
    "balancer": {
      "public_name": "my-public-alb",
      "private_name": "my-private-alb"
    },
    "dns": {
      "type": "route53"
    },
    "networking": {
      "alb_reconciliation_enabled": "false"
    },
    "deployment": {
      "image_pull_secrets": {
        "ENABLED": true,
        "SECRETS": ["ecr-secret", "dockerhub-secret"]
      },
      "traffic_container_image": "custom.ecr.aws/traffic-manager:v2.0",
      "pod_disruption_budget": {
        "enabled": "true",
        "max_unavailable": "1"
      },
      "traffic_manager_config_map": "custom-nginx-config",
      "strategy": "blue-green",
      "max_wait_seconds": 600,
      "iam": {
        "ENABLED": true,
        "PREFIX": "my-app-scopes",
        "ROLE": {
          "POLICIES": [
            {
              "TYPE": "arn",
              "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
            }
          ]
        }
      }
    },
    "manifest_backup": {
      "ENABLED": false,
      "TYPE": "s3",
      "BUCKET": "my-backup-bucket",
      "PREFIX": "k8s-manifests"
    },
    "vault": {
      "address": "https://vault.example.com",
      "token": "s.xxxxxxxxxxxxx"
    }
  }
}
```

### Configuración Mínima

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "staging"
    },
    "region": "eu-west-1"
  }
}
```

## Variables de Entorno

Puedes sobreescribir cualquier valor usando variables de entorno:

```bash
# Kubernetes
export NAMESPACE_OVERRIDE="my-custom-namespace"
export CREATE_K8S_NAMESPACE_IF_NOT_EXIST="false"
export K8S_MODIFIERS='{"global":{"labels":{"team":"platform"}}}'

# DNS & Networking
export DNS_TYPE="azure"
export ALB_RECONCILIATION_ENABLED="true"

# Deployment
export IMAGE_PULL_SECRETS='{"ENABLED":true,"SECRETS":["my-secret"]}'
export TRAFFIC_CONTAINER_IMAGE="custom.ecr.aws/traffic:v1.0"
export POD_DISRUPTION_BUDGET_ENABLED="true"
export POD_DISRUPTION_BUDGET_MAX_UNAVAILABLE="2"
export TRAFFIC_MANAGER_CONFIG_MAP="my-config-map"
export DEPLOY_STRATEGY="blue-green"
export DEPLOYMENT_MAX_WAIT_IN_SECONDS="900"
export IAM='{"ENABLED":true,"PREFIX":"my-app"}'

# Manifest Backup
export MANIFEST_BACKUP='{"ENABLED":true,"TYPE":"s3","BUCKET":"my-backups","PREFIX":"manifests/"}'

# Vault Integration
export VAULT_ADDR="https://vault.mycompany.com"
export VAULT_TOKEN="s.abc123xyz789"

# Gateway & Balancer
export PUBLIC_GATEWAY_NAME="gateway-prod"
export PRIVATE_GATEWAY_NAME="gateway-internal-prod"
```

## Variables Adicionales (Solo values.yaml)

Las siguientes variables están definidas en `k8s/values.yaml` pero **aún no están integradas** con el sistema de jerarquía scope-configuration. Solo se pueden configurar mediante `values.yaml`:

| Variable | Descripción | values.yaml | Default | Archivos que la usan |
|----------|-------------|-------------|---------|---------------------|
| **DEPLOYMENT_TEMPLATE** | Path al template de deployment | `configuration.DEPLOYMENT_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/deployment.yaml.tpl"` | Workflows de deployment |
| **SECRET_TEMPLATE** | Path al template de secrets | `configuration.SECRET_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/secret.yaml.tpl"` | Workflows de deployment |
| **SCALING_TEMPLATE** | Path al template de scaling/HPA | `configuration.SCALING_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/scaling.yaml.tpl"` | Workflows de scaling |
| **SERVICE_TEMPLATE** | Path al template de service | `configuration.SERVICE_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/service.yaml.tpl"` | Workflows de deployment |
| **PDB_TEMPLATE** | Path al template de Pod Disruption Budget | `configuration.PDB_TEMPLATE` | `"$SERVICE_PATH/deployment/templates/pdb.yaml.tpl"` | Workflows de deployment |
| **INITIAL_INGRESS_PATH** | Path al template de ingress inicial | `configuration.INITIAL_INGRESS_PATH` | `"$SERVICE_PATH/deployment/templates/initial-ingress.yaml.tpl"` | Workflows de ingress |
| **BLUE_GREEN_INGRESS_PATH** | Path al template de ingress blue-green | `configuration.BLUE_GREEN_INGRESS_PATH` | `"$SERVICE_PATH/deployment/templates/blue-green-ingress.yaml.tpl"` | Workflows de ingress |
| **SERVICE_ACCOUNT_TEMPLATE** | Path al template de service account | `configuration.SERVICE_ACCOUNT_TEMPLATE` | `"$SERVICE_PATH/scope/templates/service-account.yaml.tpl"` | Workflows de IAM |

> **Nota**: Estas variables son paths a templates y están pendientes de migración al sistema de jerarquía scope-configuration. Actualmente solo pueden configurarse en `values.yaml` o mediante variables de entorno sin soporte para providers.

### IAM Configuration

```yaml
IAM:
  ENABLED: false
  PREFIX: nullplatform-scopes
  ROLE:
    POLICIES:
      - TYPE: arn
        VALUE: arn:aws:iam::aws:policy/AmazonS3FullAccess
      - TYPE: inline
        VALUE: |
          {
            "Version": "2012-10-17",
            "Statement": [...]
          }
    BOUNDARY_ARN: arn:aws:iam::aws:policy/AmazonS3FullAccess
```

### Manifest Backup Configuration

```yaml
MANIFEST_BACKUP:
  ENABLED: false
  TYPE: s3
  BUCKET: my-backup-bucket
  PREFIX: k8s-manifests
```

## Detalles de Variables Importantes

### K8S_MODIFIERS

Permite agregar annotations, labels y tolerations a recursos de Kubernetes. Estructura:

```json
{
  "global": {
    "annotations": { "key": "value" },
    "labels": { "key": "value" }
  },
  "service": {
    "annotations": { "service.beta.kubernetes.io/aws-load-balancer-type": "nlb" }
  },
  "ingress": {
    "annotations": { "alb.ingress.kubernetes.io/scheme": "internet-facing" }
  },
  "deployment": {
    "annotations": { "prometheus.io/scrape": "true" },
    "labels": { "app-tier": "backend" },
    "tolerations": [
      {
        "key": "dedicated",
        "operator": "Equal",
        "value": "production",
        "effect": "NoSchedule"
      }
    ]
  },
  "secret": {
    "labels": { "encrypted": "true" }
  }
}
```

### IMAGE_PULL_SECRETS

Configuración para descargar imágenes de registries privados:

```json
{
  "ENABLED": true,
  "SECRETS": [
    "ecr-secret",
    "dockerhub-secret"
  ]
}
```

### POD_DISRUPTION_BUDGET

Asegura alta disponibilidad durante actualizaciones. `max_unavailable` puede ser:
- **Porcentaje**: `"25%"` - máximo 25% de pods no disponibles
- **Número absoluto**: `"1"` - máximo 1 pod no disponible

### DEPLOY_STRATEGY

Estrategia de deployment a utilizar:
- **`rolling`** (default): Deployment progresivo, pods nuevos reemplazan gradualmente a los viejos
- **`blue-green`**: Deployment side-by-side, cambio instantáneo de tráfico entre versiones

### IAM

Configuración para integración con AWS IAM. Permite asignar roles de IAM a los service accounts de Kubernetes:

```json
{
  "ENABLED": true,
  "PREFIX": "my-app-scopes",
  "ROLE": {
    "POLICIES": [
      {
        "TYPE": "arn",
        "VALUE": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
      },
      {
        "TYPE": "inline",
        "VALUE": "{\"Version\":\"2012-10-17\",\"Statement\":[...]}"
      }
    ],
    "BOUNDARY_ARN": "arn:aws:iam::aws:policy/PowerUserAccess"
  }
}
```

Cuando está habilitado, crea un service account con nombre `{PREFIX}-{SCOPE_ID}` y lo asocia con el role de IAM configurado.

### DNS_TYPE

Especifica el tipo de DNS provider para gestionar registros DNS:

- **`route53`** (default): Amazon Route53
- **`azure`**: Azure DNS
- **`external_dns`**: External DNS para integración con otros providers

```json
{
  "dns": {
    "type": "route53"
  }
}
```

### MANIFEST_BACKUP

Configuración para realizar backups automáticos de los manifiestos de Kubernetes aplicados:

```json
{
  "manifest_backup": {
    "ENABLED": true,
    "TYPE": "s3",
    "BUCKET": "my-k8s-backups",
    "PREFIX": "prod/manifests"
  }
}
```

Propiedades:
- **`ENABLED`**: Habilita o deshabilita el backup (boolean)
- **`TYPE`**: Tipo de storage para backups (actualmente solo `"s3"`)
- **`BUCKET`**: Nombre del bucket S3 donde se guardan los backups
- **`PREFIX`**: Prefijo/path dentro del bucket para organizar los manifiestos

### VAULT Integration

Integración con HashiCorp Vault para gestión de secrets:

```json
{
  "vault": {
    "address": "https://vault.example.com",
    "token": "s.xxxxxxxxxxxxx"
  }
}
```

Propiedades:
- **`address`**: URL completa del servidor Vault (debe incluir protocolo https://)
- **`token`**: Token de autenticación para acceder a Vault

Cuando está configurado, el sistema puede obtener secrets desde Vault en lugar de usar Kubernetes Secrets nativos.

> **Nota de Seguridad**: Nunca commits el token de Vault en código. Usa variables de entorno o sistemas de gestión de secrets para inyectar el token en runtime.

### DEPLOYMENT_MAX_WAIT_IN_SECONDS

Tiempo máximo (en segundos) que el sistema esperará a que un deployment se vuelva ready antes de considerarlo fallido:

- **Default**: `600` (10 minutos)
- **Valores recomendados**:
  - Aplicaciones ligeras: `300` (5 minutos)
  - Aplicaciones pesadas o con inicialización lenta: `900` (15 minutos)
  - Aplicaciones con migrations complejas: `1200` (20 minutos)

```json
{
  "deployment": {
    "max_wait_seconds": 600
  }
}
```

### ALB_RECONCILIATION_ENABLED

Habilita la reconciliación automática de Application Load Balancers. Cuando está habilitado, el sistema verifica y actualiza la configuración del ALB para mantenerla sincronizada con la configuración deseada:

- **`"true"`**: Reconciliación habilitada
- **`"false"`** (default): Reconciliación deshabilitada

```json
{
  "networking": {
    "alb_reconciliation_enabled": "true"
  }
}
```

### TRAFFIC_MANAGER_CONFIG_MAP

Si se especifica, debe ser un ConfigMap existente con:
- `nginx.conf` - Configuración principal de nginx
- `default.conf` - Configuración del virtual host

## Validación de Configuración

El JSON Schema está disponible en `/scope-configuration.schema.json` en la raíz del proyecto.

Para validar tu configuración:

```bash
# Usando ajv-cli
ajv validate -s scope-configuration.schema.json -d your-config.json

# Usando jq (validación básica)
jq empty your-config.json && echo "Valid JSON"
```

## Ejemplos de Uso

### Desarrollo Local

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "dev-local",
      "create_namespace_if_not_exist": "true"
    },
    "networking": {
      "domain_name": "dev.local"
    }
  }
}
```

### Producción con Alta Disponibilidad

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production",
      "modifiers": {
        "deployment": {
          "tolerations": [
            {
              "key": "dedicated",
              "operator": "Equal",
              "value": "production",
              "effect": "NoSchedule"
            }
          ]
        }
      }
    },
    "region": "us-east-1",
    "deployment": {
      "pod_disruption_budget": {
        "enabled": "true",
        "max_unavailable": "1"
      }
    }
  }
}
```

### Múltiples Registries

```json
{
  "scope-configuration": {
    "deployment": {
      "image_pull_secrets": {
        "ENABLED": true,
        "SECRETS": [
          "ecr-secret",
          "dockerhub-secret",
          "gcr-secret"
        ]
      }
    }
  }
}
```

### Integración con Vault y Backups

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "production"
    },
    "vault": {
      "address": "https://vault.company.com",
      "token": "s.abc123xyz"
    },
    "manifest_backup": {
      "ENABLED": true,
      "TYPE": "s3",
      "BUCKET": "prod-k8s-backups",
      "PREFIX": "scope-manifests/"
    },
    "deployment": {
      "max_wait_seconds": 900
    }
  }
}
```

### DNS Personalizado con Azure

```json
{
  "scope-configuration": {
    "kubernetes": {
      "namespace": "staging"
    },
    "dns": {
      "type": "azure"
    },
    "networking": {
      "domain_name": "staging.example.com",
      "alb_reconciliation_enabled": "true"
    }
  }
}
```

## Tests

Las configuraciones están completamente testeadas con BATS:

```bash
# Ejecutar todos los tests
make test-unit MODULE=k8s

# Tests específicos
./testing/run_bats_tests.sh k8s/utils/tests        # Tests de get_config_value
./testing/run_bats_tests.sh k8s/scope/tests        # Tests de scope/build_context
./testing/run_bats_tests.sh k8s/deployment/tests   # Tests de deployment/build_context
```

**Total: 59 tests cubriendo todas las variables y jerarquías de configuración** ✅
- 11 tests en `k8s/utils/tests/get_config_value.bats`
- 26 tests en `k8s/scope/tests/build_context.bats`
- 22 tests en `k8s/deployment/tests/build_context.bats`

## Archivos Relacionados

- **Función de utilidad**: `k8s/utils/get_config_value` - Implementa la jerarquía de configuración
- **Build contexts**:
  - `k8s/scope/build_context` - Contexto de scope
  - `k8s/deployment/build_context` - Contexto de deployment
- **Schema**: `/scope-configuration.schema.json` - JSON Schema completo
- **Defaults**: `k8s/values.yaml` - Valores por defecto del scope tipo
- **Tests**:
  - `k8s/utils/tests/get_config_value.bats`
  - `k8s/scope/tests/build_context.bats`
  - `k8s/deployment/tests/build_context.bats`

## Contribuir

Al agregar nuevas variables de configuración:

1. Actualizar `k8s/scope/build_context` o `k8s/deployment/build_context` usando `get_config_value`
2. Agregar la propiedad en `scope-configuration.schema.json`
3. Documentar el default en `k8s/values.yaml` si aplica
4. Crear tests en el archivo `.bats` correspondiente
5. Actualizar este README
