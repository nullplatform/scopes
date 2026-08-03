{
  "name": "Kill instances",
  "type": "custom",
  "icon": "material-symbols:delete-outline",
  "results": {
    "schema": { "type": "object", "required": [], "properties": {} },
    "values": {}
  },
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": { "type": "object", "required": [], "properties": {} },
    "values": {}
  },
  "annotations": {
    "show_on": ["performance"],
    "runs_over": "scope"
  }
}