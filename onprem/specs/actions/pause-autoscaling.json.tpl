{
  "name": "Pause autoscaling",
  "type": "custom",
  "icon": "material-symbols:pause-circle-outline",
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
  },
  "enabled_when": ".service.attributes.scaling_type == \"auto\""
}