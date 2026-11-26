# datadog (compatibility overlay)

Deprecated. The k8s metric step picks Prometheus or Datadog from the
organization's metrics provider (see `k8s/metric/build_context`), so nothing
new should point here.

It stays for channels created before that, which pass
`--overrides-path=<scopes checkout>/datadog` to the entrypoint: the two
workflows force `METRICS_SOURCE=datadog` on the base step, so those channels
keep querying Datadog, and keep failing with "There is no Datadog provider
configured" when the organization has none, as before. Drop the
`--overrides-path` from the channel to let the provider decide.
