#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd kubectl

if ! kubectl version --request-timeout='5s' >/dev/null 2>&1; then
  echo "Kubernetes cluster unreachable from current kubectl context."
  echo "Run: kubectl cluster-info"
  exit 1
fi

TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"
LOCAL_PORT="${LOCAL_PORT:-8080}"
TRAEFIK_PORT="${TRAEFIK_PORT:-80}"

SERVICE_NAME="$(kubectl get svc -n "${TRAEFIK_NAMESPACE}" -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "${SERVICE_NAME}" ]]; then
  echo "Unable to find Traefik service in namespace ${TRAEFIK_NAMESPACE}."
  exit 1
fi

echo "Port-forwarding ${TRAEFIK_NAMESPACE}/${SERVICE_NAME} ${LOCAL_PORT}:${TRAEFIK_PORT}"
kubectl -n "${TRAEFIK_NAMESPACE}" port-forward svc/"${SERVICE_NAME}" "${LOCAL_PORT}:${TRAEFIK_PORT}"
