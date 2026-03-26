# MISE POC - Local Agent

POC para validar el uso de [mise](https://mise.jdx.dev/) en entornos de agente para instalar herramientas definidas en `mise.toml`.

## Requisitos

- Docker
- `NP_API_KEY` exportada en tu shell
- Contexto de Kubernetes `test` configurado en `~/.kube/config`

## Levantar el agente local

Desde la raíz del repo:

```bash
./agent/start_dev.sh
```

Esto construye la imagen Docker y levanta el agente local conectado a nullplatform.

## Canal de notificaciones

El canal configurado para esta POC es:

https://kwik-e-mart.app.nullplatform.io/settings/notifications/channels/593601403

## Disparar una prueba

1. Ir a la notificación:
   https://kwik-e-mart.app.nullplatform.io/settings/notifications/272a3f48-bcc3-4794-8873-55d0d701b78f

2. Hacer **Resend** para que el agente local la procese.

## Output esperado

En los logs del agente deberías ver:

```
[DEBUG] Trusting mise config...
[DEBUG] Starting mise install...
[DEBUG] mise install done (exit code: 0)
[DEBUG] mise ls output:
github:kwik-e-mart/scim-logs-fetcher  0.1.0
[DEBUG] Running scim-logs-fetcher --version...
Hello from scim-logs-fetcher! (OS: linux, Arch: arm64)
[DEBUG] scim-logs-fetcher done (exit code: 0)
```

Esto confirma que mise instaló correctamente `scim-logs-fetcher 0.1.0` desde GitHub y lo ejecutó con éxito.
