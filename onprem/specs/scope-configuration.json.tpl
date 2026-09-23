{
  "name": "Containers On-Premise",
  "description": "Scope configuration for clusters with no cloud provider behind them, where the zone the cluster serves has nowhere else to come from",
  "category": "scope-configurations",
  "icon": "mdi:server-network",
  "visible_to": [
    "{{ env.Getenv "NRN" }}"
  ],
  "allow_dimensions": true,
  "schema": {
    "type": "object",
    "required": [
      "networking"
    ],
    "properties": {
      "networking": {
        "type": "object",
        "order": 1,
        "title": "Networking",
        "required": [
          "domain_name"
        ],
        "properties": {
          "domain_name": {
            "type": "string",
            "order": 1,
            "title": "Domain name",
            "description": "Zone the cluster serves, under which public scope records are published. On a cluster with a cloud behind it this comes from the cloud provider; without one, this is the only place it can be stated."
          },
          "private_domain_name": {
            "type": "string",
            "order": 2,
            "title": "Private domain name",
            "description": "Zone used for scopes whose visibility is private. Left unset, private scopes fall back to the public zone above."
          }
        }
      }
    }
  }
}
