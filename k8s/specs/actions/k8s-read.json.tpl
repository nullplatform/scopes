{
  "name": "Read Kubernetes objects",
  "slug": "k8s-read",
  "type": "custom",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "scope_id",
        "command"
      ],
      "properties": {
        "scope_id": {
          "type": "number",
          "readOnly": true,
          "visibleOn": ["read"]
        },
        "command": {
          "type": "string",
          "enum": ["get", "logs"],
          "description": "kubectl verb to run. Only read-only verbs are available"
        },
        "args": {
          "type": "array",
          "maxItems": 30,
          "items": {
            "type": "string"
          },
          "description": "Arguments for the verb, one per item, e.g. [\"pods\", \"-o\", \"wide\"]. Only read-only flags are accepted, and a short flag takes its value as the next item"
        }
      }
    },
    "values": {}
  },
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {
        "exit_code": {
          "type": "number"
        },
        "output": {
          "type": "string"
        },
        "error": {
          "type": "string"
        },
        "truncated": {
          "type": "boolean"
        },
        "namespace": {
          "type": "string"
        }
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": [],
    "runs_over": "scope"
  }
}
