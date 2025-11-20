{
  "assignable_to": "any",
  "available_actions":[
    "create-scope",
    "delete-scope",
    "start-initial",
    "start-blue-green",
    "finalize-blue-green",
    "rollback-deployment",
    "delete-deployment",
    "switch-traffic",
    "set-desired-instance-count",
    "pause-autoscaling",
    "resume-autoscaling",
    "restart-pods",
    "kill-instances"
  ],
  "agent_command":{
    "data": {
      "cmdline": "nullplatform/scopes/entrypoint --service-path=k8s",
      "environment": {
        "NP_ACTION_CONTEXT": "'${NOTIFICATION_CONTEXT}'"
       }
     },
    "type": "exec"
  },
  "attributes": {
   "schema":{
      "type":"object",
      "required":[
         "ram_memory",
         "visibility",
         "autoscaling",
         "health_check",
         "scaling_type",
         "cpu_millicores",
         "fixed_instances",
         "scheduled_stop",
         "additional_ports",
         "continuous_delivery"
      ],
      "uiSchema":{
         "type":"VerticalLayout",
         "elements":[
            {
               "type":"Control",
               "label":"RAM Memory",
               "scope":"#/properties/ram_memory"
            },
            {
               "type":"Control",
               "label":"Visibility",
               "scope":"#/properties/visibility",
               "options":{
                  "format":"radio"
               }
            },
            {
               "type":"Categorization",
               "options":{
                  "collapsable":{
                     "label":"ADVANCED",
                     "collapsed":true
                  }
               },
               "elements":[
                  {
                     "type":"Category",
                     "label":"Processor",
                     "elements":[
                        {
                           "type":"Control",
                           "label":"CPU Millicores",
                           "scope":"#/properties/cpu_millicores"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Size & Scaling",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/scaling_type"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scaling_type",
                                 "schema":{
                                    "enum":[
                                       "fixed"
                                    ]
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/fixed_instances"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scaling_type",
                                 "schema":{
                                    "enum":[
                                       "auto"
                                    ]
                                 }
                              }
                           },
                           "type":"Group",
                           "label":"Autoscaling Settings",
                           "elements":[
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/min_replicas"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/max_replicas"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/target_cpu_utilization"
                              },
                              {
                                 "rule": {
                                   "effect": "SHOW",
                                   "condition": {
                                     "scope": "#/properties/autoscaling/properties/target_memory_enabled",
                                     "schema": {
                                       "const": true
                                     }
                                   }
                                 },
                                 "type": "Control",
                                 "scope": "#/properties/autoscaling/properties/target_memory_utilization"
                              }
                           ]
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Additional Ports",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/additional_ports",
                           "options":{
                              "detail":{
                                 "type":"VerticalLayout",
                                 "elements":[
                                    {
                                       "type":"Control",
                                       "scope":"#/properties/port"
                                    },
                                    {
                                       "type":"Control",
                                       "scope":"#/properties/type"
                                    }
                                 ]
                              }
                           }
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Scheduled Stop",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/scheduled_stop/properties/enabled"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/scheduled_stop/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/scheduled_stop/properties/timer"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Continuous deployment",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/continuous_delivery/properties/enabled"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/continuous_delivery/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/continuous_delivery/properties/branches"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Health Check",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/enabled"
                        },
                        {
                          "rule": {
                            "effect": "SHOW",
                            "condition": {
                              "scope": "#/properties/health_check/properties/enabled",
                              "schema": {
                                "const": true
                              }
                            }
                          },
                          "type": "Control",
                          "scope": "#/properties/health_check/properties/type",
                          "options":{
                            "format":"radio"
                          }
                        },
                        {
                          "rule": {
                            "effect": "SHOW",
                            "condition": {
                              "type": "AND",
                              "conditions": [
                                {
                                  "scope": "#/properties/health_check/properties/type",
                                  "schema": {
                                    "const": "HTTP"
                                  }
                                },
                                {
                                  "scope": "#/properties/health_check/properties/enabled",
                                  "schema": {
                                    "const": true
                                  }
                                }
                              ]
                            }
                          },
                          "type": "Control",
                          "scope": "#/properties/health_check/properties/path"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/initial_delay_seconds"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/period_seconds"
                        },
                        {
                           "rule":{
                              "effect":"SHOW",
                              "condition":{
                                 "scope":"#/properties/health_check/properties/enabled",
                                 "schema":{
                                    "const":true
                                 }
                              }
                           },
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/timeout_seconds"
                        }
                     ]
                  }
               ]
            }
         ]
      },
      "properties":{
         "asset_type":{
            "type":"string",
            "export":false,
            "default":"docker-image"
         },
         "ram_memory":{
            "type":"integer",
            "oneOf":[
               {
                  "const":64,
                  "title":"64 MB"
               },
               {
                  "const":128,
                  "title":"128 MB"
               },
               {
                  "const":256,
                  "title":"256 MB"
               },
               {
                  "const":512,
                  "title":"512 MB"
               },
               {
                  "const":1024,
                  "title":"1 GB"
               },
               {
                  "const":2048,
                  "title":"2 GB"
               },
               {
                  "const":4096,
                  "title":"4 GB"
               },
               {
                  "const":8192,
                  "title":"8 GB"
               },
               {
                  "const":16384,
                  "title":"16 GB"
               }
            ],
            "title":"RAM Memory",
            "default":256,
            "description":"Amount of RAM memory to allocate to the container (in MB)"
         },
         "visibility":{
            "type":"string",
            "oneOf":[
               {
                  "const":"internal",
                  "title":"Publicly Accessible",
                  "description":"Exposed and reachable from outside your private network"
               }
            ],
            "title":"Visibility",
            "default":"internal",
            "description":"Define whether the scope is publicly accessible or private to your account"
         },
         "autoscaling":{
            "type":"object",
            "properties":{
               "max_replicas":{
                  "type":"integer",
                  "title":"Maximum Replicas",
                  "default":5,
                  "maximum":20,
                  "minimum":1,
                  "description":"Maximum number of instances to scale to"
               },
               "min_replicas":{
                  "type":"integer",
                  "title":"Minimum Replicas",
                  "default":1,
                  "maximum":10,
                  "minimum":1,
                  "description":"Minimum number of instances to maintain"
               },
               "target_cpu_utilization":{
                  "type":"integer",
                  "title":"Target CPU Utilization (%)",
                  "default":70,
                  "maximum":90,
                  "minimum":50,
                  "description":"CPU utilization threshold that triggers scaling"
               },
               "target_memory_enabled": {
                 "type": "boolean",
                 "title": "Scale by memory",
                 "default": false
               },
               "target_memory_utilization": {
                 "type": "integer",
                 "title": "Target memory utilization (%)",
                 "default": 70,
                 "maximum": 90,
                 "minimum": 50,
                 "description": "Memory utilization threshold that triggers scaling"
               }
            }
         },
         "health_check":{
            "type":"object",
            "properties":{
               "path":{
                  "type":"string",
                  "title":"Health Check Path",
                  "default":"/health",
                  "description":"HTTP path for health check requests"
               },
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Health Check",
                  "default":true
               },
               "period_seconds":{
                  "type":"integer",
                  "title":"Check Interval",
                  "default":10,
                  "maximum":300,
                  "minimum":1,
                  "description":"Seconds between health checks"
               },
               "timeout_seconds":{
                  "type":"integer",
                  "title":"Timeout",
                  "default":5,
                  "maximum":60,
                  "minimum":1,
                  "description":"Seconds to wait for a health check response"
               },
               "initial_delay_seconds":{
                  "type":"integer",
                  "title":"Initial Delay",
                  "default":30,
                  "maximum":300,
                  "minimum":0,
                  "description":"Seconds to wait before starting health checks"
               },
               "type": {
                 "type": "string",
                 "title": "Health check type",
                 "default": "HTTP",
                 "enum": [
                   "HTTP",
                   "TCP"
                 ],
                 "description": "To be applied in startup, readiness and liveness probes"
               }
            }
         },
         "scaling_type":{
            "enum":[
               "fixed",
               "auto"
            ],
            "type":"string",
            "title":"Scaling Type",
            "default":"fixed",
            "description":"Choose between fixed number of instances or automatic scaling"
         },
         "cpu_millicores":{
            "type":"integer",
            "title":"CPU Millicores",
            "default":100,
            "maximum":4000,
            "minimum":100,
            "description":"Amount of CPU to allocate (in millicores, 1000m = 1 CPU core)"
         },
         "scheduled_stop":{
            "type":"object",
            "title":"Scheduled Stop",
            "required":[
               "enabled",
               "timer"
            ],
            "properties":{
               "timer":{
                  "type":"string",
                  "oneOf":[
                     {
                        "const":"3600",
                        "title":"1 hour"
                     },
                     {
                        "const":"10800",
                        "title":"3 hours"
                     },
                     {
                        "const":"21600",
                        "title":"6 hours"
                     },
                     {
                        "const":"43200",
                        "title":"12 hours"
                     },
                     {
                        "const":"tonight",
                        "title":"Tonight"
                     }
                  ],
                  "title":"Stop After",
                  "default":"3600",
                  "description":"When to automatically stop the service"
               },
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Scheduled Stop",
                  "default":false,
                  "description":"Automatically stop the service after a specified time"
               }
            },
            "description":"Configure automatic stopping of the service"
         },
         "fixed_instances":{
            "type":"integer",
            "title":"Number of Instances",
            "default":1,
            "maximum":10,
            "minimum":1,
            "description":"Fixed number of instances to run"
         },
         "additional_ports":{
            "type":"array",
            "items":{
               "type":"object",
               "required":[
                  "port",
                  "type"
               ],
               "properties":{
                  "port":{
                     "type":"integer",
                     "title":"Port Number",
                     "maximum":65535,
                     "minimum":1024,
                     "description":"The port number to expose (1024-65535)"
                  },
                  "type":{
                     "enum":[
                        "GRPC"
                     ],
                     "type":"string",
                     "title":"Port Type",
                     "description":"The protocol type for this port"
                  }
               }
            },
            "title":"Additional Ports",
            "default":[

            ],
            "description":"Configure additional ports for your application"
         },
         "continuous_delivery":{
            "type":"object",
            "title":"Continuous Delivery",
            "required":[
               "enabled",
               "branches"
            ],
            "properties":{
               "enabled":{
                  "type":"boolean",
                  "title":"Enable Continuous Delivery",
                  "default":false,
                  "description":"Automatically deploy new versions from specified branches"
               },
               "branches":{
                  "type":"array",
                  "items":{
                     "type":"string"
                  },
                  "title":"Branches",
                  "default":[
                     "main"
                  ],
                  "description":"Git branches to monitor for automatic deployment"
               }
            },
            "description":"Configure automatic deployment from Git branches"
         },
         "custom_domains": {
            "type": "object",
            "required": [
               "enabled"
            ],
            "properties": {
               "enabled": {
               "type": "boolean",
               "default": true
               }
            }
         }
      }
   }
  },
  "name": "Containers",
  "selectors": {
    "category": "any",
    "imported": false,
    "provider": "any",
    "sub_category": "any"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ]
}
