{
  "name": "Trigger job",
  "type": "custom",
  "icon": "material-symbols:play-circle-outline-rounded",
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
      ],
      "properties": {
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": [
      "scope"
    ],
    "runs_over": "scope"
  }
}