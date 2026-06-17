# Parameters Package — Pending Work

Status snapshot del estado actual del paquete `parameters/` y trabajo pendiente. Para una vista de la arquitectura completa ver `parameters/docs/architecture.md`.

---

## Estado actual

| Componente | Estado |
|---|---|
| Skeleton (entrypoint, build_context, dispatch, utils, workflows) | ✅ Implementado |
| Provider `hashicorp_vault` | ✅ Implementado (migrado del `parameters/vault/` original) |
| Provider `secret_manager` | ✅ Implementado |
| Provider `parameter_store` | ✅ Implementado (nuevo) |
| Provider `azure_key_vault` | ✅ Implementado (nuevo) |
| Error handling (not_found → idempotent, otros → fail loud) | ✅ Aplicado a deletes y retrieves de los 4 providers |
| Tests BATS | ✅ 150 tests pasando |
| Docs globales | ✅ architecture.md, configuration.md, adding_a_provider.md |
| Docs por provider | ✅ architecture.md (4 providers), iam-policy.md (SM + PS) |
| Decision doc para equipo | ✅ `aws-secret-manager-strategies.docx` (en root del repo) |
| Naming NRN+slug-based | ⏳ Pendiente — ver "1. Refactor de naming" |
| `fetch_configuration` por provider | ⏳ Pendiente — ver "2. Placeholders" |

---

## Decisiones tomadas

| Decisión | Valor | Origen |
|---|---|---|
| Estrategia de granularidad | 1:1 mapping (un secret por parámetro) | Review del equipo sobre el decision doc |
| Naming convention | NRN entities con slugs+ids + dimensiones + parameter_id | Conversación de diseño |
| Provider AWS Secrets Manager | Nombre futuro: `aws_secret_manager` (rename pendiente de `secret_manager`) | Conversación de diseño |
| Selector resolution | Env-only (`SECRET_PROVIDER`, `PARAMETER_PROVIDER`) | Limitación del provider-categories de nullplatform |
| Workflow YAMLs | 4 workflows unificados (store, retrieve, delete, notify), sin discriminación por kind | Cleanup arquitectónico |
| Discriminación secret/param | En `build_context` desde `$CONTEXT.secret`, no en entrypoint | Mismo cleanup |
| Logging | Todos los niveles routean a stderr (stdout reservado para JSON) | Bug encontrado durante tests |
| Delete failure semantics | "not found" → success idempotente, todo lo demás → exit 1 con troubleshooting | Feedback de revisión |
| Retrieve failure semantics | Idem delete: "not found" → `{value: "value not found"}`, otros errores → exit 1 | Idem |

---

## Pendiente

### 1. Refactor de naming a NRN+slugs+ids

**Bloqueado por:** falta confirmar la syntax exacta del `np` CLI para obtener slugs de entities por ID.

**Hipótesis (a confirmar antes de implementar):**

```bash
np organization get --id 1255165411 --query slug --output text
```

#### Diseño aprobado

El `external_id` retornado a nullplatform (y por tanto el nombre del secret en cada provider) se compone así:

```
<entity_type>=<slug>-<id>/<entity_type>=<slug>-<id>/.../<dim_key>=<dim_value>/<parameter_id>
```

- Entities iteradas en orden NRN canónico: `organization → account → namespace → application → scope`. Solo se incluyen las presentes.
- Dimensiones ordenadas alfabéticamente por key para garantizar determinismo.
- `parameter_id` al final como identificador único.
- Slugs son inmutables en nullplatform (garantía del contrato), por lo que el external_id no sufre deriva en el tiempo.

#### Ejemplo

Con `entities = {organization: "1255165411", account: "95118862", namespace: "37094320", application: "321402625"}`, `dimensions = {env: "prod"}`, `parameter_id = 42`:

```
organization=acme-1255165411/account=prod-95118862/namespace=billing-37094320/application=api-321402625/env=prod/42
```

#### Pasos

1. Crear `parameters/utils/build_external_id` con fetch paralelo de slugs vía `np` CLI (usando `mktemp` + `&` + `wait`).
2. Refactorizar `store` de los 4 providers:
   - `hashicorp_vault/store`: nombre `secret/data/parameters/<external_id>`
   - `secret_manager/store`: nombre `<SM_NAME_PREFIX><external_id>`
   - `parameter_store/store`: nombre `<PS_NAME_PREFIX><external_id>`
   - `azure_key_vault/store`: nombre `<AZ_SECRET_PREFIX><external_id transformado>`. AKV solo permite alfanumérico + `-`, así que transformamos `/` → `-` y removemos `=`.
3. `retrieve`/`delete`/`notify` NO cambian: usan el `EXTERNAL_ID` que llega de nullplatform.
4. Tests: mock de `np` CLI en `$BATS_TEST_TMPDIR/bin/`, expected paths actualizados en cada provider.
5. Update de `parameters/providers/<name>/docs/architecture.md` con el nuevo naming.

#### Edge cases (todos confirmados)

- Entities siempre vienen (parte del contrato de nullplatform) — no hay caso de "entities vacío".
- `np` CLI siempre está disponible (instalado en la imagen Docker base del agente).
- Slugs inmutables — no hay riesgo de deriva o reconstrucción incorrecta.

---

### 2. Placeholders `fetch_configuration` por provider

Cada provider necesita un placeholder `fetch_configuration` (opcional según el contrato pero útil) que populate `PROVIDER_CONFIG` con su config específica desde donde corresponda (np CLI, REST, file, etc.).

Hoy todos los providers funcionan vía env vars (`VAULT_ADDR`, `AWS_REGION`, etc.). El placeholder permite wirear el fetch real cuando el platform team defina el mecanismo.

Estructura sugerida:

```bash
#!/bin/bash
# parameters/providers/<name>/fetch_configuration
#
# TODO(platform-team): wire la lógica de fetch real (np CLI, REST, file montado, etc.)
# Mientras tanto, PROVIDER_CONFIG default a '{}' y todo cae a env vars.

: "${PROVIDER_CONFIG:=}"
if [ -z "$PROVIDER_CONFIG" ]; then
  PROVIDER_CONFIG='{}'
fi
export PROVIDER_CONFIG
```

A duplicar en los 4 providers. Build_context ya sourcea `$PROVIDER_DIR/fetch_configuration` si existe.

---

### 3. Rename `secret_manager` → `aws_secret_manager` (opcional)

Decisión tomada en conversación pero no aplicada todavía. No bloqueante para nada. Cuando se haga:

- Mover `parameters/providers/secret_manager/` → `parameters/providers/aws_secret_manager/`
- Update referencias en docs (architecture.md, configuration.md, adding_a_provider.md, iam-policy.md)
- Update tests en `parameters/tests/providers/secret_manager/` (mover y renombrar)
- Actualizar valores aceptables de `SECRET_PROVIDER` / `PARAMETER_PROVIDER` en docs

---

## Contrato del payload — para referencia rápida

Notification de nullplatform tiene estos campos en `$CONTEXT` (después de que el entrypoint extrae `.notification`):

| Campo | Tipo | Acciones | Notas |
|---|---|---|---|
| `parameter_id` | number | store, notify | nullplatform parameter ID |
| `value` | string | store | el valor a persistir |
| `external_id` | string | retrieve, delete, notify | handle generado en store (NRN+slugs+ids+dims+id) |
| `secret` | bool | todas | discriminador secret/parameter (sigue derivando PARAMETER_KIND pero no afecta routing en 1:1) |
| `parameter_name` | string | todas | display name del parámetro |
| `encoding` | string | todas | `plain`, `base64`, etc. |
| `entities` | object | todas | IDs only — slugs se fetchean por separado vía np CLI |
| `value_entities` | object | retrieve (opcional) | Mismo formato que entities, solo presente si el value tiene NRN distinto al parámetro |
| `dimensions` | object | opcional | key-value pairs (env, country, etc.) — ordenarse alfabéticamente |

Las entities siempre vienen como IDs strings:

```json
{
  "organization": "1255165411",
  "account": "95118862",
  "namespace": "37094320",
  "application": "321402625"
}
```

---

## Cómo correr los tests

```bash
bats $(find parameters/tests -name "*.bats")
```

Distribución actual (150 tests):

- Skeleton (entrypoint, build_context, dispatch, utils): 55 tests
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
├── entrypoint, build_context           # router + provider resolution
├── store, retrieve, delete, notify     # dispatch one-liners
├── workflows/                          # 4 YAMLs (acción-only, kind se deriva)
├── utils/
│   ├── get_config_value                # priority: provider config > env > default
│   └── log                             # todos los niveles a stderr
├── providers/
│   ├── README.md                       # contrato del provider
│   ├── hashicorp_vault/
│   ├── secret_manager/
│   ├── parameter_store/
│   └── azure_key_vault/
├── tests/                              # 150 BATS tests
└── docs/                               # docs globales del paquete
```
