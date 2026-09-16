terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

locals {
  # otel/opentelemetry-collector-contrib, not the core image: the prometheus and
  # otlphttp exporters used below live in contrib, not core.
  otel_collector_default_values = <<-YAML
    mode: deployment
    fullnameOverride: otel-collector
    image:
      repository: otel/opentelemetry-collector-contrib
    config:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
      exporters:
        otlp/tempo:
          endpoint: tempo.${var.namespace}.svc.cluster.local:4317
          tls:
            insecure: true
        otlphttp/loki:
          endpoint: http://loki.${var.namespace}.svc.cluster.local:3100/otlp
          tls:
            insecure: true
        prometheus:
          endpoint: 0.0.0.0:8889
          # WITHOUT THIS, RESOURCE ATTRIBUTES ARE NOT METRIC LABELS. An OTLP metric carries
          # its Resource (service.name, and everything in the sender's
          # OTEL_RESOURCE_ATTRIBUTES) separately from the datapoint's own attributes. This
          # exporter maps datapoint attributes to Prometheus labels and, by default, drops the
          # Resource — so `reliever_events_published_total` arrived with `routing_key` but with
          # NO `capability_id`, `zone`, `deployable` or `environment`, and a dashboard could not
          # break the product down by capability. ADR-TECH-STRAT-005 Rule 8 makes those four
          # mandatory ON EVERY METRIC, which is a statement about what arrives here, not only
          # about what senders set.
          resource_to_telemetry_conversion:
            enabled: true
      service:
        pipelines:
          traces:
            receivers: [otlp]
            exporters: [otlp/tempo]
          logs:
            receivers: [otlp]
            exporters: [otlphttp/loki]
          metrics:
            receivers: [otlp]
            exporters: [prometheus]
    ports:
      prometheus:
        enabled: true
        containerPort: 8889
        servicePort: 8889
        protocol: TCP
  YAML

  prometheus_default_values = <<-YAML
    alertmanager:
      enabled: false
    prometheus-pushgateway:
      enabled: false
    prometheus-node-exporter:
      enabled: false
    kube-state-metrics:
      enabled: false
    extraScrapeConfigs: |
      - job_name: otel-collector
        static_configs:
          - targets: ['otel-collector.${var.namespace}.svc.cluster.local:8889']
  YAML

  loki_default_values = <<-YAML
    deploymentMode: SingleBinary
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h
    singleBinary:
      replicas: 1
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
    gateway:
      enabled: false
    lokiCanary:
      enabled: false
    test:
      enabled: false
    chunksCache:
      enabled: false
    resultsCache:
      enabled: false
  YAML

  tempo_default_values = <<-YAML
    tempo:
      storage:
        trace:
          backend: local
          local:
            path: /var/tempo/traces
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
  YAML

  # Loki datasource carries a derived field that turns trace_id in a log line into
  # a link to the matching Tempo trace; Tempo's own datasource carries the reverse
  # link (tracesToLogsV2) so a trace can jump back to its correlated log lines.
  grafana_default_values = <<-YAML
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
          - name: Prometheus
            # A STABLE uid, because a provisioned dashboard references a datasource BY uid, not
            # by name. Without one Grafana assigns a random uid per install, so a dashboard
            # ConfigMap that names `prometheus` renders "Datasource not found" on every panel —
            # and would do so again after any reinstall even if it were corrected by hand. Loki
            # and Tempo below already carry theirs.
            uid: prometheus
            type: prometheus
            access: proxy
            url: http://prometheus-server.${var.namespace}.svc.cluster.local
          - name: Loki
            uid: loki
            type: loki
            access: proxy
            url: http://loki.${var.namespace}.svc.cluster.local:3100
            jsonData:
              derivedFields:
                - datasourceUid: tempo
                  matcherRegex: 'trace_id=(\w+)'
                  name: TraceID
                  url: "$${__value.raw}"
          - name: Tempo
            uid: tempo
            type: tempo
            access: proxy
            # 3200, NOT 3100. Tempo's HTTP query API listens on 3200; 3100 is LOKI's port, and
            # the two were transposed here. The symptom is not an obvious failure: the
            # datasource saves, panels just return nothing, and "Test" reports failure in a way
            # easy to read as "no traces yet". Verified against the running Service, which
            # publishes 3200 (and 4317 for ingest) and no 3100 at all.
            url: http://tempo.${var.namespace}.svc.cluster.local:3200
            isDefault: true
            jsonData:
              tracesToLogsV2:
                datasourceUid: loki
                spanStartTimeShift: "-1h"
                spanEndTimeShift: "1h"
                filterByTraceID: true
    sidecar:
      dashboards:
        enabled: true
        label: grafana_dashboard
        labelValue: "1"
        searchNamespace: ALL
        folderAnnotation: grafana_folder
        provider:
          name: sidecar
          disableDelete: false
          allowUiUpdates: false
          foldersFromFilesStructure: true
  YAML

  elasticsearch_default_values = <<-YAML
    replicas: 1
    minimumMasterNodes: 1
    esJavaOpts: "-Xmx512m -Xms512m"
    resources:
      requests:
        cpu: 100m
        memory: 1Gi
      limits:
        cpu: 1000m
        memory: 1Gi
    volumeClaimTemplate:
      resources:
        requests:
          storage: 5Gi
  YAML

  kibana_default_values = <<-YAML
    elasticsearchHosts: "http://elasticsearch-master.${var.namespace}.svc.cluster.local:9200"
  YAML
}

resource "helm_release" "otel_collector" {
  count = var.enable_otel_collector ? 1 : 0

  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.otel_collector_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.otel_collector_values_yaml == null ? [local.otel_collector_default_values] : [local.otel_collector_default_values, var.otel_collector_values_yaml]

  dynamic "set" {
    for_each = var.otel_collector_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "prometheus" {
  count = var.enable_prometheus ? 1 : 0

  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = var.prometheus_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.prometheus_values_yaml == null ? [local.prometheus_default_values] : [local.prometheus_default_values, var.prometheus_values_yaml]

  dynamic "set" {
    for_each = var.prometheus_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "loki" {
  count = var.enable_loki ? 1 : 0

  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = var.loki_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.loki_values_yaml == null ? [local.loki_default_values] : [local.loki_default_values, var.loki_values_yaml]

  dynamic "set" {
    for_each = var.loki_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "tempo" {
  count = var.enable_tempo ? 1 : 0

  name             = "tempo"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  version          = var.tempo_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.tempo_values_yaml == null ? [local.tempo_default_values] : [local.tempo_default_values, var.tempo_values_yaml]

  dynamic "set" {
    for_each = var.tempo_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = var.grafana_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.grafana_values_yaml == null ? [local.grafana_default_values] : [local.grafana_default_values, var.grafana_values_yaml]

  dynamic "set" {
    for_each = var.grafana_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "elasticsearch" {
  count = var.enable_elasticsearch_kibana ? 1 : 0

  name             = "elasticsearch"
  repository       = "https://helm.elastic.co"
  chart            = "elasticsearch"
  version          = var.elasticsearch_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.elasticsearch_values_yaml == null ? [local.elasticsearch_default_values] : [local.elasticsearch_default_values, var.elasticsearch_values_yaml]

  dynamic "set" {
    for_each = var.elasticsearch_set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}

resource "helm_release" "kibana" {
  count = var.enable_elasticsearch_kibana ? 1 : 0

  name             = "kibana"
  repository       = "https://helm.elastic.co"
  chart            = "kibana"
  version          = var.kibana_chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  values = var.kibana_values_yaml == null ? [local.kibana_default_values] : [local.kibana_default_values, var.kibana_values_yaml]

  dynamic "set" {
    for_each = var.kibana_set_values
    content {
      name  = set.key
      value = set.value
    }
  }

  depends_on = [helm_release.elasticsearch]
}
