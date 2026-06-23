# Parameters Package — Pending Work

Status snapshot del estado actual del paquete `parameters/` y trabajo pendiente. Para vista de la arquitectura completa: `parameters/docs/architecture.md`.

---

## Estado actual

| Componente | Estado |
|---|---|
| Skeleton (entrypoint, build_context, dispatch, utils, workflows) | ✅ Implementado |
| Provider `hashicorp_vault` | ✅ Implementado |
| Provider `aws_secret_manager` | ✅ Implementado |
| Provider `parameter_store` | ✅ Implementado |
| Provider `azure_key_vault` | ✅ Implementado |
| Error handling (not_found → idempotent, otros → fail loud) | ✅ Aplicado a deletes y retrieves |
| Tests BATS | ✅ 151 tests pasando |
| Docs globales | ✅ architecture.md, configuration.md, adding_a_provider.md |
| Docs por provider | ✅ architecture.md (4 providers), iam-policy.md (SM + PS) |
| Decision doc para equipo | ✅ `aws-secret-manager-strategies.docx` (en root del repo) |
| **Resolución de provider via `provider.specification_id`** | **✅ Implementado** (era pendiente, hecho hoy) |
| **`PROVIDER_CONFIG` desde `provider.attributes`** | **✅ Implementado** (era pendiente como `fetch_configuration`, ahora viene en payload) |
| Naming NRN+slug-based | ✅ Implementado (utils/build_external_id + 4 providers refactorizados) |
| Rename `secret_manager` → `aws_secret_manager` | ✅ Implementado |

---

## Decisiones tomadas

| Decisión | Valor | Origen |
|---|---|---|
| Estrategia de granularidad | 1:1 mapping (un secret por parámetro) | Review del equipo sobre el decision doc |
| Naming convention | NRN entities con slugs+ids + dimensiones + parameter_id | Conversación de diseño |
| Provider AWS Secrets Manager | Nombre futuro: `aws_secret_manager` | Conversación de diseño |
| Provider selection | Via `provider.specification_id` → np CLI → slug | Cambio reciente con payload real |
| Provider config source | `provider.attributes` en el payload (no env vars, no fetch script) | Cambio reciente |
| Workflow YAMLs | 4 workflows unificados (store, retrieve, delete, notify) | Cleanup arquitectónico |
| Discriminación secret/param | En `build_context` desde `$CONTEXT.secret`, no en entrypoint | Cleanup |
| Logging | Todos los niveles routean a stderr (stdout reservado para JSON) | Bug encontrado durante tests |
| Delete failure semantics | "not found" → success idempotente, otros → exit 1 | Feedback de revisión |
| Retrieve failure semantics | Idem delete | Feedback de revisión |

---

## Pendiente

Sin items pendientes a la fecha. Todas las decisiones aprobadas están implementadas.

---

## Contrato del payload — referencia rápida

`$CONTEXT` (después de que el entrypoint extrae `.notification`):

| Campo | Tipo | Acciones | Notas |
|---|---|---|---|
| `parameter_id` | number | todas | nullplatform parameter ID |
| `value` | string | store | el valor a persistir |
| `external_id` | string | retrieve, delete, notify | handle generado en store |
| `secret` | bool | todas | discriminador secret/parameter (informativo en 1:1) |
| `parameter_name` | string | todas | display name |
| `encoding` | string | todas | `plain`, `base64`, etc. |
| `entities` | object | todas | IDs only — slugs vía np CLI (solo en store, para naming) |
| `dimensions` | object | opcional | top-level, NO en `provider.dimensions` |
| `provider.specification_id` | uuid | todas | **el que decide qué provider usar** |
| `provider.attributes` | object | todas | **config del provider, viene en el payload** |
| `provider.nrn` | string | todas | informacional (NRN del provider instance) |
| `provider.dimensions` | object | todas | informacional (dimensions del provider instance) |
| `provider.id` | uuid | todas | informacional |

Ejemplo de payload completo de store:

```json
{
  "action": "parameter:store",
  "parameter_id": 359535238,
  "value": "the-value",
  "parameter_name": "test_param",
  "secret": false,
  "encoding": "plaintext",
  "entities": {
    "organization": "1255165411",
    "account": "95118862",
    "namespace": "37094320",
    "application": "321402625"
  },
  "dimensions": {
    "environment": "development",
    "country": "argentina"
  },
  "provider": {
    "id": "e4105634-4ee0-4ffa-996b-1fb8213e56b6",
    "nrn": "organization=1255165411:account=95118862:namespace=37094320:application=321402625",
    "dimensions": {},
    "specification_id": "ec885dd0-7c38-45b8-af2c-0b9e1deb7d3d",
    "attributes": {}
  }
}
```

---

## Cómo correr los tests

```bash
bats $(find parameters/tests -name "*.bats")
```

Distribución actual (151 tests):

- Skeleton (entrypoint, build_context, dispatch, utils): 56 tests
- hashicorp_vault: 27 tests
- aws_secret_manager: 17 tests (renombrado desde `secret_manager`)
- parameter_store: 23 tests
- azure_key_vault: 15 tests
- utils/log + utils/get_config_value: 13 tests

---

## Estructura del paquete

```
parameters/
├── PENDING.md                          # este archivo
├── entrypoint, build_context           # router + provider resolution via spec_id
├── store, retrieve, delete, notify     # dispatch one-liners
├── workflows/                          # 4 YAMLs (acción-only)
├── utils/
│   ├── get_config_value                # priority: provider config > env > default
│   └── log                             # todos los niveles a stderr
├── providers/
│   ├── README.md                       # contrato del provider
│   ├── hashicorp_vault/
│   ├── aws_secret_manager/
│   ├── parameter_store/
│   └── azure_key_vault/
├── tests/                              # 151 BATS tests
└── docs/                               # docs globales del paquete
```
