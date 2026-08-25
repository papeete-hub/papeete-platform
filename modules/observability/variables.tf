variable "namespace" {
  description = "Namespace every observability component is installed into."
  type        = string
  default     = "observability"
}

variable "create_namespace" {
  description = "Whether Helm should create var.namespace if it doesn't already exist."
  type        = bool
  default     = true
}

# --- OpenTelemetry Collector ----------------------------------------------

variable "enable_otel_collector" {
  description = "Install the OTel Collector (receives OTLP traces/logs/metrics on gRPC 4317, fans out to Tempo/Loki/Prometheus)."
  type        = bool
  default     = true
}

variable "otel_collector_chart_version" {
  description = "opentelemetry-collector chart version to install (unpinned installs whatever Helm resolves as latest)."
  type        = string
  default     = null
}

variable "otel_collector_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "otel_collector_values_yaml" {
  description = "A full Helm values.yaml document (as a string) layered on top of this module's default Collector pipeline (OTLP gRPC receiver on 4317, fanned out to the Tempo/Loki/Prometheus exporters below). Leave null to use that default as-is."
  type        = string
  default     = null
}

# --- Prometheus (metrics) ---------------------------------------------------

variable "enable_prometheus" {
  description = "Install Prometheus (server-only — alertmanager/pushgateway/node-exporter/kube-state-metrics subcharts disabled)."
  type        = bool
  default     = true
}

variable "prometheus_chart_version" {
  description = "prometheus chart version to install."
  type        = string
  default     = null
}

variable "prometheus_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "prometheus_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's server-only default (which also scrapes the Collector's Prometheus exporter). Leave null to use that default as-is."
  type        = string
  default     = null
}

# --- Loki (logs) -------------------------------------------------------------

variable "enable_loki" {
  description = "Install Loki (monolithic/single-binary, filesystem storage). Logs arrive via OTLP push through the Collector, so no Promtail/Fluent-bit is needed."
  type        = bool
  default     = true
}

variable "loki_chart_version" {
  description = "loki chart version to install."
  type        = string
  default     = null
}

variable "loki_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "loki_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's single-binary/filesystem default. Leave null to use that default as-is."
  type        = string
  default     = null
}

# --- Tempo (traces) ----------------------------------------------------------

variable "enable_tempo" {
  description = "Install Tempo (monolithic, local storage)."
  type        = bool
  default     = true
}

variable "tempo_chart_version" {
  description = "tempo chart version to install."
  type        = string
  default     = null
}

variable "tempo_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "tempo_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's local-storage default. Leave null to use that default as-is."
  type        = string
  default     = null
}

# --- Grafana (dashboard) -------------------------------------------------------

variable "enable_grafana" {
  description = "Install Grafana, pre-provisioned with Prometheus/Loki/Tempo datasources and trace-to-logs correlation."
  type        = bool
  default     = true
}

variable "grafana_chart_version" {
  description = "grafana chart version to install."
  type        = string
  default     = null
}

variable "grafana_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "grafana_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's default datasource provisioning. Leave null to use that default as-is."
  type        = string
  default     = null
}

# --- Elasticsearch + Kibana (opt-in, default off) ------------------------------

variable "enable_elasticsearch_kibana" {
  description = "Install Elasticsearch + Kibana as a second, opt-in log store alongside Loki (a *different* store, not a replacement). Off by default: this module's default log path is OTLP push through the Collector into Loki."
  type        = bool
  default     = false
}

variable "elasticsearch_chart_version" {
  description = "elasticsearch chart version to install."
  type        = string
  default     = null
}

variable "elasticsearch_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "elasticsearch_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's single-node local-dev default. Leave null to use that default as-is."
  type        = string
  default     = null
}

variable "kibana_chart_version" {
  description = "kibana chart version to install."
  type        = string
  default     = null
}

variable "kibana_set_values" {
  description = "Chart values to override, as Helm --set-style key/value pairs."
  type        = map(string)
  default     = {}
}

variable "kibana_values_yaml" {
  description = "A full Helm values.yaml document layered on top of this module's default (which points Kibana at the Elasticsearch release above). Leave null to use that default as-is."
  type        = string
  default     = null
}
