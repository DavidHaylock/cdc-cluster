{{/* Chart name, overridable. */}}
{{- define "cdc-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "cdc-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "cdc-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cdc-app.commonLabels" -}}
helm.sh/chart: {{ include "cdc-app.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "cdc-app.name" . }}
{{- end }}

{{- define "cdc-app.api.fullname" -}}
{{- printf "%s-api" (include "cdc-app.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cdc-app.api.labels" -}}
{{ include "cdc-app.commonLabels" . }}
{{ include "cdc-app.api.selectorLabels" . }}
{{- end }}

{{- define "cdc-app.api.selectorLabels" -}}
app.kubernetes.io/name: api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end }}

{{/*
Name of the mongodb subchart release resources - mirrors common.names.fullname
from the bitnami chart so the host below tracks any name overrides.
*/}}
{{- define "cdc-app.mongodb.fullname" -}}
{{- $mongo := .Values.mongodb | default dict }}
{{- if $mongo.fullnameOverride }}
{{- $mongo.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "mongodb" $mongo.nameOverride }}
{{- $releaseName := regexReplaceAll "(-?[^a-z\\d\\-])+-?" (lower .Release.Name) "-" }}
{{- if contains $name $releaseName }}
{{- $releaseName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" $releaseName $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
MongoDB host for the API. In replicaset mode the bitnami chart only creates a
headless Service; combined with directConnection=true that resolves to a single
member, which is all the API needs.
*/}}
{{- define "cdc-app.mongodb.host" -}}
{{- if .Values.database.host }}
{{- tpl .Values.database.host . }}
{{- else if eq (default "standalone" .Values.mongodb.architecture) "replicaset" }}
{{- printf "%s-headless" (include "cdc-app.mongodb.fullname" .) }}
{{- else }}
{{- include "cdc-app.mongodb.fullname" . }}
{{- end }}
{{- end }}

{{/* DATABASE_URL for the API. */}}
{{- define "cdc-app.databaseUrl" -}}
{{- $db := .Values.database }}
{{- if $db.url }}
{{- tpl $db.url . }}
{{- else }}
{{- $host := include "cdc-app.mongodb.host" . }}
{{- $rs := default "rs0" .Values.mongodb.replicaSetName }}
{{- printf "mongodb://%s:%v/%s?directConnection=%v&retryWrites=true&w=majority&replicaSet=%s" $host $db.port $db.name $db.directConnection $rs }}
{{- end }}
{{- end }}
