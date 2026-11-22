{
  "name": "Read Kubernetes objects",
  "slug": "k8s-read",
  "type": "custom",
  "retryable": true,
  "service_specification_id": "{{ env.Getenv "SERVICE_SPECIFICATION_ID" }}",
  "parameters": {
    "schema": {
      "type": "object",
      "required": [
        "scope_id",
        "command"
      ],
      "properties": {
        "scope_id": {
          "type": "number",
          "readOnly": true,
          "visibleOn": [
            "read"
          ]
        },
        "command": {
          "type": "string",
          "enum": [
            "get",
            "logs"
          ],
          "description": "kubectl verb to run. Only read-only verbs are available"
        },
        "args": {
          "type": "array",
          "maxItems": 30,
          "items": {
            "type": "string",
            "maxLength": 500
          },
          "description": "Arguments for the verb, one per item, e.g. [\"pods\", \"-o\", \"wide\"]. For get, the first item is the resource type (or type/name) from a fixed list that leaves secrets out. Only read-only flags are accepted, and a short flag takes its value as the next item"
        }
      },
      "allOf": [
        {
          "if": {
            "properties": {
              "command": {
                "const": "get"
              }
            }
          },
          "then": {
            "required": [
              "args"
            ],
            "properties": {
              "args": {
                "minItems": 1,
                "items": [
                  {
                    "type": "string",
                    "maxLength": 500,
                    "pattern": "^(pods|pod|po|deployments|deployment|deploy|replicasets|replicaset|rs|statefulsets|statefulset|sts|daemonsets|daemonset|ds|jobs|job|cronjobs|cronjob|cj|replicationcontrollers|replicationcontroller|rc|services|service|svc|endpoints|ep|endpointslices|endpointslice|ingresses|ingress|ing|ingressclasses|ingressclass|networkpolicies|networkpolicy|netpol|events|event|ev|configmaps|configmap|cm|horizontalpodautoscalers|horizontalpodautoscaler|hpa|verticalpodautoscalers|verticalpodautoscaler|vpa|poddisruptionbudgets|poddisruptionbudget|pdb|persistentvolumeclaims|persistentvolumeclaim|pvc|persistentvolumes|persistentvolume|pv|storageclasses|storageclass|sc|serviceaccounts|serviceaccount|sa|nodes|node|no|namespaces|namespace|ns|resourcequotas|resourcequota|quota|limitranges|limitrange|limits|leases|lease|priorityclasses|priorityclass|pc|httproutes|httproute|grpcroutes|grpcroute|gateways|gateway|gtw|gatewayclasses|gatewayclass|gc|referencegrants|referencegrant|gateways[.]gateway[.]networking[.]k8s[.]io|gateways[.]networking[.]istio[.]io|virtualservices|virtualservice|vs|destinationrules|destinationrule|dr|serviceentries|serviceentry|se|authorizationpolicies|authorizationpolicy|peerauthentications|peerauthentication|requestauthentications|requestauthentication|sidecars|sidecar|envoyfilters|envoyfilter|targetgroupbindings|targetgroupbinding|ingressclassparams|scaledobjects|scaledobject|so|scaledjobs|scaledjob|sj|certificates|certificate|cert|certificaterequests|certificaterequest|cr|nodepools|nodepool|nodeclaims|nodeclaim|ec2nodeclasses|ec2nodeclass)(/[a-z0-9][a-z0-9.-]*)?$"
                  }
                ],
                "additionalItems": {
                  "type": "string",
                  "maxLength": 500,
                  "pattern": "^([^-].*|-n|-l|-o|-L|-A|--namespace(=.+)?|--selector(=.+)?|--output(=(json|yaml|wide|name|jsonpath=.*|jsonpath-as-json=.*|custom-columns=.*))?|--sort-by(=.+)?|--field-selector(=.+)?|--label-columns(=.+)?|--all-namespaces|--show-labels|--no-headers|--show-kind|--ignore-not-found)$",
                  "not": {
                    "pattern": "^[sS][eE][cC][rR][eE][tT][sS]?([./,]|$)"
                  }
                }
              }
            }
          }
        },
        {
          "if": {
            "properties": {
              "command": {
                "const": "logs"
              }
            }
          },
          "then": {
            "properties": {
              "args": {
                "items": {
                  "type": "string",
                  "maxLength": 500,
                  "pattern": "^([^-].*|-n|-l|-c|-p|--namespace(=.+)?|--selector(=.+)?|--container(=.+)?|--tail(=-?[0-9]+)?|--since(=.+)?|--since-time(=.+)?|--max-log-requests(=[0-9]+)?|--limit-bytes(=[0-9]+)?|--all-containers|--previous|--timestamps|--prefix)$"
                }
              }
            }
          }
        }
      ]
    },
    "values": {}
  },
  "results": {
    "schema": {
      "type": "object",
      "required": [],
      "properties": {
        "exit_code": {
          "type": "number"
        },
        "output": {
          "type": "string"
        },
        "error": {
          "type": "string"
        },
        "truncated": {
          "type": "boolean"
        },
        "namespace": {
          "type": "string"
        }
      }
    },
    "values": {}
  },
  "annotations": {
    "show_on": [],
    "runs_over": "scope"
  }
}
