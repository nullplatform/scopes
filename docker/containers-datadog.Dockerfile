# syntax=docker/dockerfile:1
#
# containers-datadog — the containers scope with the datadog overlay baked in
# (the datadog/ folder overrides the metric step). The containers base already
# COPYied the whole repo into /app/pkg (incl. datadog/), so this only layers the
# overlay onto the service-path. datadog uses jq + curl, already in the base.
# BASE_IMAGE lets the beta workflow build on the containers beta of the same pull request.
ARG BASE_IMAGE=public.ecr.aws/nullplatform/scopes/containers
ARG BASE_VERSION
FROM ${BASE_IMAGE}:${BASE_VERSION}

ENV NP_PACKAGE_NAME=containers-datadog \
    NP_OVERRIDES_PATH=/app/pkg/datadog
