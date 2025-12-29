{
  "name": "Diagnose Deployment",
  "slug": "diagnose-deployment",
  "type": "diagnose",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "scope_id",
        "deployment_id"
      ],
      "properties": {
        "scope_id": {
          "type": "string",
          "readOnly": true
        },
        "deployment_id": {
          "type": "string",
          "readOnly": true
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