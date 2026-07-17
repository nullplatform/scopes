{
  "name": "Kill instance",
  "type": "custom",
  "icon": "material-symbols:delete-outline",
  "results": {
    "schema": { "type": "object", "required": [], "properties": {} },
    "values": {}
  },
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": ["instance_id"],
      "properties": {
        "instance_id": { "type": "string" }
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": ["performance"],
    "runs_over": "scope"
  }
}