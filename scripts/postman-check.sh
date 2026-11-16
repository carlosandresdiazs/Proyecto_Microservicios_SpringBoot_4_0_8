#!/usr/bin/env bash
set -euo pipefail
NAMESPACE="proyecto-03"
echo "Revisando contexto y recursos..."
kubectl config current-context
kubectl -n "$NAMESPACE" get deploy,svc,pods,pvc
kubectl -n "$NAMESPACE" rollout status deployment/api-gateway --timeout=180s
kubectl -n "$NAMESPACE" rollout status deployment/keycloak --timeout=180s
cat <<'TXT'
Abra dos terminales distintas (mantenga ambas abiertas):
  kubectl -n proyecto-03 port-forward svc/api-gateway 8080:8080
  kubectl -n proyecto-03 port-forward svc/keycloak 8085:8080
Luego importe postman/Proyecto03_Kubernetes_REST.postman_collection.json
junto con postman/Proyecto03_Kubernetes_Local.postman_environment.json.
TXT
