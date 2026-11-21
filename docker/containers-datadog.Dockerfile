# syntax=docker/dockerfile:1
#
# containers-datadog: the containers scope with metrics from Datadog. The worker
# answers metric:list and metric:data from Datadog's API (worker/src/metrics/
# datadog.ts) with the keys the environment or the organization's metrics
# provider holds; logs and instances come from the cluster as on containers.
# BASE_IMAGE lets the beta workflow build on the containers beta of the same pull request.
ARG BASE_IMAGE=public.ecr.aws/nullplatform/scopes/containers
ARG BASE_VERSION
FROM ${BASE_IMAGE}:${BASE_VERSION}

ENV NP_PACKAGE_NAME=containers-datadog \
    METRICS_BACKEND=datadog
