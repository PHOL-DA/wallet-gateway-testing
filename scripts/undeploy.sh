#!/usr/bin/env bash
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd helm
require_cmd kubectl

CONFIG_FILE="${CONFIG_FILE:-config/defaults.env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  set -a
  source "${CONFIG_FILE}"
  set +a
fi

NAMESPACE="${NAMESPACE:-wallet-stack}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"

DELETE_NAMESPACES="${DELETE_NAMESPACES:-true}"

if ! kubectl version --request-timeout='5s' >/dev/null 2>&1; then
  echo "Kubernetes cluster unreachable from current kubectl context."
  exit 1
fi

uninstall_if_present() {
  local release="$1"
  local namespace="$2"
  if helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    echo "Uninstalling Helm release ${namespace}/${release}"
    helm uninstall "${release}" -n "${namespace}" --wait
  else
    echo "Helm release ${namespace}/${release} not found, skipping"
  fi
}

uninstall_if_present "wallet-gateway" "${NAMESPACE}"
uninstall_if_present "splice-portfolio" "${NAMESPACE}"
uninstall_if_present "traefik" "${TRAEFIK_NAMESPACE}"

if [[ "${DELETE_NAMESPACES}" == "true" ]]; then
  if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Deleting namespace ${NAMESPACE}"
    kubectl delete namespace "${NAMESPACE}" --wait=true
  fi

  if kubectl get namespace "${TRAEFIK_NAMESPACE}" >/dev/null 2>&1; then
    echo "Deleting namespace ${TRAEFIK_NAMESPACE}"
    kubectl delete namespace "${TRAEFIK_NAMESPACE}" --wait=true
  fi
fi

echo ""
echo "Stack reset complete."
