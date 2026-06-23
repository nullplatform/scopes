# Parameters Package — Pending Work

Status snapshot del estado actual del paquete `parameters/` y trabajo pendiente. Para vista de la arquitectura completa: `parameters/docs/architecture.md`.

---

## Estado actual

| Componente | Estado |
|---|---|
| Skeleton (entrypoint, build_context, dispatch, utils, workflows) | ✅ Implementado |
| Provider `hashicorp_vault` | ✅ Implementado |
| Provider `secret_manager` | ✅ Implementado (renombre a `aws_secret_manager` pendiente) |
| Provider `parameter_store` | ✅ Implementado |
| Provider `azure_key_vault` | ✅ Implementado |
| Error handling (not_found → idempotent, otros → fail loud) | ✅ Aplicado a deletes y retrieves |
| Tests BATS | ✅ 151 tests pasando |
| Docs globales | ✅ architecture.md, configuration.md, adding_a_provider.md |
| Docs por provider | ✅ architecture.md (4 providers), iam-policy.md (SM + PS) |
| Decision doc para equipo | ✅ `aws-secret-manager-strategies.docx` (en root del repo) |
| **Resolución de provider via `provider.specification_id`** | **✅ Implementado** (era pendiente, hecho hoy) |
| **`PROVIDER_CONFIG` desde `provider.attributes`** | **✅ Implementado** (era pendiente como `fetch_configuration`, ahora viene en payload) |
| Naming NRN+slug-based | ⏳ Pendiente — ver "1. Refactor de naming" |
| Rename `secret_manager` → `aws_secret_manager` | ⏳ Pendiente (opcional, no bloqueante) |

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

### 1. Refactor de naming a NRN+slugs+ids

**Bloqueado por:** confirmar syntax exacta del `np` CLI para obtener slugs de entities por ID.

**Hipótesis (a confirmar antes de implementar):**

```bash
np organization get --id 1255165411 --output json
# → { "slug": "acme", "id": "1255165411", ... }
```

#### Diseño aprobado

El `external_id` retornado a nullplatform (y por tanto el nombre del secret en cada provider) se compone así:

```
<entity_type>=<slug>-<id>/<entity_type>=<slug>-<id>/.../<dim_key>=<dim_value>/<parameter_id>
```

- Entities iteradas en orden NRN canónico: `organization → account → namespace → application → scope`. Solo se incluyen las presentes.
- Dimensiones (desde `$CONTEXT.dimensions`, top-level, no `provider.dimensions`) ordenadas alfabéticamente por key.
- `parameter_id` al final como identificador único.
- Slugs son inmutables en nullplatform (garantía del contrato), por lo que el external_id no sufre deriva.

#### Ejemplo

Con `entities = {organization: "1255165411", account: "95118862", namespace: "37094320", application: "321402625"}`, `dimensions = {environment: "development", country: "argentina"}`, `parameter_id = 359535238`:

```
organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/country=argentina/environment=development/359535238
```

#### Pasos

1. Crear `parameters/utils/build_external_id` con fetch paralelo de slugs vía `np` CLI (usando `mktemp` + `&` + `wait`).
2. Refactorizar `store` de los 4 providers:
   - `hashicorp_vault/store`: nombre `secret/data/parameters/<external_id>`
   - `secret_manager/store`: nombre `<SM_NAME_PREFIX><external_id>`
   - `parameter_store/store`: nombre `<PS_NAME_PREFIX><external_id>`
   - `azure_key_vault/store`: AKV solo permite alfanumérico + `-`, transformar `/` → `-` y remover `=`.
3. `retrieve`/`delete`/`notify` NO cambian: usan el `EXTERNAL_ID` que llega de nullplatform.
4. Tests: mock de `np <entity> get` en `$BATS_TEST_TMPDIR/bin/`, expected paths actualizados.
5. Update de `parameters/providers/<name>/docs/architecture.md` con el nuevo naming.

#### Edge cases (todos confirmados)

- Entities siempre vienen (parte del contrato de nullplatform).
- `np` CLI siempre está disponible (instalado en la imagen Docker base del agente).
- Slugs inmutables — no hay riesgo de deriva o reconstrucción incorrecta.

---

### 2. Rename `secret_manager` → `aws_secret_manager` (opcional)

Decisión tomada pero no aplicada. No bloqueante. Cuando se haga:

- Mover `parameters/providers/secret_manager/` → `parameters/providers/aws_secret_manager/`
- Update referencias en docs
- Update tests en `parameters/tests/providers/secret_manager/` (mover y renombrar)

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
- secret_manager: 17 tests
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
│   ├── secret_manager/
│   ├── parameter_store/
│   └── azure_key_vault/
├── tests/                              # 151 BATS tests
└── docs/                               # docs globales del paquete
```
