{
  "name": "Diagnose Deployment",
  "slug": "diagnose-deployment",
  "type": "custom",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "deployment_id"
      ],
      "properties": {
        "deployment_id": {
          "type": "string"
        }
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": [
      "deployment"
    ],
    "runs_over": "deployment"
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