{
  "assignable_to": "any",
  "attributes": {
   "schema":{
      "type":"object",
      "required":[
         "memory",
         "health_check",
         "scaling_type",
         "fixed_instances",
         "websockets_enabled",
         "continuous_delivery"
      ],
      "uiSchema":{
         "type":"VerticalLayout",
         "elements":[
            {
               "type":"Control",
               "label":"Memory",
               "scope":"#/properties/memory"
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
                                 "scope":"#/properties/autoscaling/properties/min_instances"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/max_instances"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/target_cpu_utilization"
                              },
                              {
                                 "type":"Control",
                                 "scope":"#/properties/autoscaling/properties/target_memory_enabled"
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
                     "label":"Runtime",
                     "elements":[
                        {
                           "type":"Control",
                           "label":"WebSockets",
                           "scope":"#/properties/websockets_enabled"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Health Check",
                     "elements":[
                        {
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/path"
                        },
                        {
                           "type":"Control",
                           "scope":"#/properties/health_check/properties/eviction_time_in_min"
                        }
                     ]
                  },
                  {
                     "type":"Category",
                     "label":"Continuous Deployment",
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
         "memory":{
            "type":"integer",
            "oneOf":[
               {
                  "const":2,
                  "title":"2 GB"
               },
               {
                  "const":4,
                  "title":"4 GB"
               },
               {
                  "const":8,
                  "title":"8 GB"
               },
               {
                  "const":16,
                  "title":"16 GB"
               },
               {
                  "const":32,
                  "title":"32 GB"
               }
            ],
            "title":"Memory",
            "default":2,
            "description":"Memory allocation in GB for your application"
         },
         "websockets_enabled":{
            "type":"boolean",
            "title":"Enable WebSockets",
            "default":false,
            "description":"Enable WebSocket protocol support for real-time communication"
         },
         "scaling_type":{
            "enum":[
               "fixed",
               "auto"
            ],
            "type":"string",
            "title":"Scaling Type",
            "default":"fixed",
            "description":"Choose between fixed number of instances or automatic scaling based on load"
         },
         "fixed_instances":{
            "type":"integer",
            "title":"Number of Instances",
            "default":1,
            "maximum":10,
            "minimum":1,
            "description":"Fixed number of instances to run"
         },
         "autoscaling":{
            "type":"object",
            "properties":{
               "min_instances":{
                  "type":"integer",
                  "title":"Minimum Instances",
                  "default":1,
                  "maximum":10,
                  "minimum":1,
                  "description":"Minimum number of instances to maintain"
               },
               "max_instances":{
                  "type":"integer",
                  "title":"Maximum Instances",
                  "default":10,
                  "maximum":30,
                  "minimum":1,
                  "description":"Maximum number of instances to scale to"
               },
               "target_cpu_utilization":{
                  "type":"integer",
                  "title":"CPU Scale-Out Threshold (%)",
                  "default":70,
                  "maximum":90,
                  "minimum":50,
                  "description":"CPU percentage that triggers scale out"
               },
               "target_memory_enabled": {
                 "type": "boolean",
                 "title": "Scale by Memory",
                 "default": false
               },
               "target_memory_utilization": {
                 "type": "integer",
                 "title": "Memory Scale-Out Threshold (%)",
                 "default": 75,
                 "maximum": 90,
                 "minimum": 50,
                 "description": "Memory percentage that triggers scale out"
               }
            }
         },
         "health_check":{
            "type":"object",
            "properties":{
               "path":{
                  "type":"string",
                  "title":"Health Check Path",
                  "description":"HTTP path for health check requests (e.g., /health). Leave empty to disable health checks."
               },
               "eviction_time_in_min":{
                  "type":"integer",
                  "title":"Unhealthy Instance Eviction Time",
                  "default":1,
                  "maximum":60,
                  "minimum":1,
                  "description":"Minutes before an unhealthy instance is removed and replaced"
               }
            }
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
  "name": "Azure App Service",
  "selectors": {
    "category": "Scope",
    "imported": false,
    "provider": "Agent",
    "sub_category": "App Service"
  },
  "type": "scope",
  "use_default_actions": false,
  "visible_to": [
    "{{ env.Getenv \"NRN\" }}"
  ]
}
