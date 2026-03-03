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
require_cmd envsubst

chart_version() {
  local chart_ref="$1"
  local requested_version="${2:-}"
  if [[ -n "${requested_version}" ]]; then
    helm show chart "${chart_ref}" --version "${requested_version}" | awk -F': ' '/^version:/{print $2; exit}'
  else
    helm show chart "${chart_ref}" | awk -F': ' '/^version:/{print $2; exit}'
  fi
}

resolve_service_name() {
  local namespace="$1"
  local release_name="$2"
  local app_label="$3"
  local service_name

  service_name="$(kubectl get svc -n "${namespace}" -l app.kubernetes.io/instance="${release_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${service_name}" ]]; then
    echo "${service_name}"
    return 0
  fi

  service_name="$(kubectl get svc -n "${namespace}" -l app="${app_label}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${service_name}" ]]; then
    echo "${service_name}"
    return 0
  fi

  service_name="$(kubectl get svc -n "${namespace}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E "^${release_name}(-|$)" | head -n1 || true)"
  echo "${service_name}"
}

resolve_deployment_name() {
  local namespace="$1"
  local release_name="$2"
  local app_label="$3"
  local deployment_name

  deployment_name="$(kubectl get deploy -n "${namespace}" -l app.kubernetes.io/instance="${release_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${deployment_name}" ]]; then
    echo "${deployment_name}"
    return 0
  fi

  deployment_name="$(kubectl get deploy -n "${namespace}" -l app="${app_label}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -n "${deployment_name}" ]]; then
    echo "${deployment_name}"
    return 0
  fi

  deployment_name="$(kubectl get deploy -n "${namespace}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E "^${release_name}(-|$)" | head -n1 || true)"
  echo "${deployment_name}"
}

if ! kubectl version --request-timeout='5s' >/dev/null 2>&1; then
  echo "Kubernetes cluster unreachable from current kubectl context."
  echo ""
  echo "Checks:"
  echo "  kubectl config current-context"
  echo "  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\\n"}'"
  echo "  kubectl cluster-info"
  echo ""
  echo "If you don't have a local cluster yet, create one (example with kind):"
  echo "  kind create cluster --name wallet-stack"
  exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-config/defaults.env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  set -a
  source "${CONFIG_FILE}"
  set +a
fi

NAMESPACE="${NAMESPACE:-wallet-stack}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"

WALLET_GATEWAY_CHART="${WALLET_GATEWAY_CHART:-oci://ghcr.io/digital-asset/wallet-gateway/helm/wallet-gateway}"
SPLICE_PORTFOLIO_CHART="${SPLICE_PORTFOLIO_CHART:-oci://ghcr.io/digital-asset/splice-portfolio/helm/splice-portfolio}"

WALLET_GATEWAY_CHART_VERSION="${WALLET_GATEWAY_CHART_VERSION:-}"
SPLICE_PORTFOLIO_CHART_VERSION="${SPLICE_PORTFOLIO_CHART_VERSION:-}"

WALLET_GATEWAY_IMAGE_TAG="${WALLET_GATEWAY_IMAGE_TAG:-}"
SPLICE_PORTFOLIO_IMAGE_TAG="${SPLICE_PORTFOLIO_IMAGE_TAG:-}"
WALLET_GATEWAY_VALUES_FILE="${WALLET_GATEWAY_VALUES_FILE:-config/wallet-gateway.values.yaml}"

helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install traefik traefik/traefik \
  --namespace "${TRAEFIK_NAMESPACE}" \
  --create-namespace \
  --set providers.kubernetesCRD.enabled=true \
  --set providers.kubernetesIngress.enabled=true \
  --wait

SP_ARGS=()
WG_ARGS=()
WG_VALUES_ARGS=()

if [[ -n "${SPLICE_PORTFOLIO_CHART_VERSION}" ]]; then
  SP_ARGS+=(--version "${SPLICE_PORTFOLIO_CHART_VERSION}")
fi

if [[ -n "${WALLET_GATEWAY_CHART_VERSION}" ]]; then
  WG_ARGS+=(--version "${WALLET_GATEWAY_CHART_VERSION}")
fi

if [[ -n "${WALLET_GATEWAY_VALUES_FILE}" ]]; then
  if [[ -f "${WALLET_GATEWAY_VALUES_FILE}" ]]; then
    WG_VALUES_ARGS+=(-f "${WALLET_GATEWAY_VALUES_FILE}")
  else
    echo "Wallet gateway values file not found: ${WALLET_GATEWAY_VALUES_FILE}"
    exit 1
  fi
fi

if [[ -z "${SPLICE_PORTFOLIO_IMAGE_TAG}" ]]; then
  SP_RESOLVED_CHART_VERSION="$(chart_version "${SPLICE_PORTFOLIO_CHART}" "${SPLICE_PORTFOLIO_CHART_VERSION}")"
  SPLICE_PORTFOLIO_IMAGE_TAG="${SP_RESOLVED_CHART_VERSION#v}"
fi

if [[ -z "${WALLET_GATEWAY_IMAGE_TAG}" ]]; then
  WG_RESOLVED_CHART_VERSION="$(chart_version "${WALLET_GATEWAY_CHART}" "${WALLET_GATEWAY_CHART_VERSION}")"
  WALLET_GATEWAY_IMAGE_TAG="${WG_RESOLVED_CHART_VERSION#v}"
fi

helm upgrade --install splice-portfolio "${SPLICE_PORTFOLIO_CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set-string image.tag="${SPLICE_PORTFOLIO_IMAGE_TAG}" \
  --wait \
  "${SP_ARGS[@]}"

helm upgrade --install wallet-gateway "${WALLET_GATEWAY_CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  "${WG_VALUES_ARGS[@]}" \
  --set-string image.tag="${WALLET_GATEWAY_IMAGE_TAG}" \
  --wait \
  "${WG_ARGS[@]}"

WALLET_DEPLOYMENT_NAME="$(resolve_deployment_name "${NAMESPACE}" "wallet-gateway" "wallet-gateway-wallet-gateway")"
if [[ -n "${WALLET_DEPLOYMENT_NAME}" ]]; then
  kubectl -n "${NAMESPACE}" rollout restart "deployment/${WALLET_DEPLOYMENT_NAME}" >/dev/null
  kubectl -n "${NAMESPACE}" rollout status "deployment/${WALLET_DEPLOYMENT_NAME}" --timeout=180s >/dev/null
fi

SPLICE_SERVICE_NAME="$(resolve_service_name "${NAMESPACE}" "splice-portfolio" "splice-portfolio-splice-portfolio")"
WALLET_SERVICE_NAME="$(resolve_service_name "${NAMESPACE}" "wallet-gateway" "wallet-gateway-wallet-gateway")"

if [[ -n "${SPLICE_SERVICE_NAME}" ]]; then
  SPLICE_SERVICE_PORT="$(kubectl get svc -n "${NAMESPACE}" "${SPLICE_SERVICE_NAME}" -o jsonpath='{.spec.ports[0].port}')"
else
  SPLICE_SERVICE_PORT=""
fi

if [[ -n "${WALLET_SERVICE_NAME}" ]]; then
  WALLET_SERVICE_PORT="$(kubectl get svc -n "${NAMESPACE}" "${WALLET_SERVICE_NAME}" -o jsonpath='{.spec.ports[0].port}')"
else
  WALLET_SERVICE_PORT=""
fi

if [[ -z "${SPLICE_SERVICE_NAME}" || -z "${WALLET_SERVICE_NAME}" || -z "${SPLICE_SERVICE_PORT}" || -z "${WALLET_SERVICE_PORT}" ]]; then
  echo "Unable to resolve service names for one or both releases."
  kubectl get svc -n "${NAMESPACE}"
  exit 1
fi

export NAMESPACE SPLICE_SERVICE_NAME SPLICE_SERVICE_PORT WALLET_SERVICE_NAME WALLET_SERVICE_PORT

envsubst < k8s/ingressroute.template.yaml | kubectl apply -f -

echo ""
echo "Deployment complete."
echo "Splice Portfolio service: ${SPLICE_SERVICE_NAME}:${SPLICE_SERVICE_PORT}"
echo "Wallet Gateway service:  ${WALLET_SERVICE_NAME}:${WALLET_SERVICE_PORT}"
echo "Run ./scripts/port-forward.sh and browse: http://localhost:8080"
echo "Wallet Gateway will be available at: http://localhost:8080/api/wallets"
