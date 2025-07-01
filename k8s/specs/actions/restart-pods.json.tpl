{
  "name": "Restart pods",
  "type": "custom",
  "icon": "material-symbols:refresh",
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {}
    },
    "values": {}
  },
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
  "annotations": {
    "show_on": [
      "performance"
    ],
    "runs_over": "scope"
  }
}