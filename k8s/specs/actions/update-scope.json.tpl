{
  "name": "update-scope",
  "slug": "update-scope",
  "type": "update",
  "retryable": false,
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
  }
}
