{{- define "extraMounts.registry" -}}
{{- if .Values.registry.deployed }}
- hostPath: {{.Values.installer.repositoryRoot}}/dev/local-registry
  containerPath: /var/installer/local-registry
{{- end }}
{{- end -}}
