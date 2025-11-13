{
  "name": "Diagnose Scope",
  "slug": "diagnose-scope",
  "type": "custom",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "scope_id"
      ],
      "properties": {
        "scope_id": {
          "type": "string"
        }
      }
    },
    "values": {}
  },
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {}
    },
    "values": {}
  },
  "annotations": {
    "show_on": [
      "scope", "deployment", "performance"
    ],
    "runs_over": "scope"
  }
}