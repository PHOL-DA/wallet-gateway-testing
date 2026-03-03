#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-wallet-stack}"
KIND_VERSION="${KIND_VERSION:-v0.27.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-v1.32.2}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"

mkdir -p "${LOCAL_BIN}"

ensure_on_path() {
  case ":$PATH:" in
    *":${LOCAL_BIN}:"*) return 0 ;;
  esac

  echo "${LOCAL_BIN} is not on PATH for this shell."
  echo "Run: export PATH=\"${LOCAL_BIN}:\$PATH\""
}

install_kind() {
  echo "Installing kind ${KIND_VERSION} to ${LOCAL_BIN}/kind"
  curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" -o "${LOCAL_BIN}/kind"
  chmod +x "${LOCAL_BIN}/kind"
}

install_kubectl() {
  echo "Installing kubectl ${KUBECTL_VERSION} to ${LOCAL_BIN}/kubectl"
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o "${LOCAL_BIN}/kubectl"
  chmod +x "${LOCAL_BIN}/kubectl"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for kind but was not found."
  echo "Install Docker first, then re-run this script."
  exit 1
fi

if ! command -v kind >/dev/null 2>&1; then
  install_kind
fi

if ! command -v kubectl >/dev/null 2>&1; then
  install_kubectl
fi

export PATH="${LOCAL_BIN}:$PATH"

if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' already exists."
else
  kind create cluster --name "${CLUSTER_NAME}"
fi

kubectl cluster-info
ensure_on_path
