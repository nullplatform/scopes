{
  "name": "Set desired instance count",
  "type": "custom",
  "icon": "material-symbols:note-add-outline",
  "results": {
    "schema": { "type": "object", "required": [], "properties": {} },
    "values": {}
  },
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": ["desired_instances"],
      "properties": {
        "desired_instances": {
          "type": "integer",
          "title": "Desired Instance Count",
          "description": "Set the number of instances you want to run",
          "additionalKeywords": {
            "default": ".service.attributes.autoscaling.min_replicas // 1",
            "maximum": ".service.attributes.autoscaling.max_replicas // 10",
            "minimum": ".service.attributes.autoscaling.min_replicas // 1"
          }
        }
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": ["performance"],
    "runs_over": "scope"
  }
}