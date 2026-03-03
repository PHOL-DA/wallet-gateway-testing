# wallet-gateway-testing

Small Helm-based local setup for:

- Splice Portfolio at `http://localhost:8080/`
- Wallet Gateway behind a sub-route at `http://localhost:8080/api/wallets`

Routing is handled by Traefik using a Kubernetes `IngressRoute` + `Middleware`.

## Prerequisites

- Kubernetes cluster (local is fine: kind, k3d, Docker Desktop, minikube)
- `kubectl`
- `helm` (v3.8+ with OCI support)

## Deploy

If you need a local Kubernetes cluster first:

```bash
make bootstrap-kind
```

Then deploy:

```bash
make deploy
```

`scripts/deploy.sh` automatically loads defaults from [config/defaults.env](config/defaults.env).
You can point to a different file with:

```bash
CONFIG_FILE=path/to/my.env make deploy
```

This does the following:

1. Installs Traefik via Helm chart in namespace `traefik`
2. Installs both OCI Helm charts into namespace `wallet-stack`
3. Detects service names/ports from installed releases
4. Applies Traefik routing so:
	- `/api/wallets` -> wallet-gateway
	- `/` -> splice-portfolio

## Expose on localhost:8080

```bash
make forward
```

Then open:

- `http://localhost:8080/`
- `http://localhost:8080/api/wallets`

## Reset / Undeploy

To uninstall both app releases and Traefik:

```bash
make down
```

Alias:

```bash
make undeploy
```

By default it also deletes the namespaces. To keep namespaces:

```bash
DELETE_NAMESPACES=false make down
```

## Configurable environment variables

You can override chart references, versions, and namespaces:

- `NAMESPACE` (default: `wallet-stack`)
- `TRAEFIK_NAMESPACE` (default: `traefik`)
- `WALLET_GATEWAY_CHART` (default: `oci://ghcr.io/digital-asset/wallet-gateway/helm/wallet-gateway`)
- `SPLICE_PORTFOLIO_CHART` (default: `oci://ghcr.io/digital-asset/splice-portfolio/helm/splice-portfolio`)
- `WALLET_GATEWAY_CHART_VERSION` (optional)
- `SPLICE_PORTFOLIO_CHART_VERSION` (optional)
- `WALLET_GATEWAY_IMAGE_TAG` (optional; defaults to chart version without leading `v`)
- `SPLICE_PORTFOLIO_IMAGE_TAG` (optional; defaults to chart version without leading `v`)
- `LOCAL_PORT` for port-forward (default: `8080`)

Example:

```bash
WALLET_GATEWAY_CHART_VERSION=0.0.0 SPLICE_PORTFOLIO_CHART_VERSION=0.0.0 make deploy
```

## Notes

- If the OCI package paths require authentication in your environment, run `helm registry login ghcr.io` first.
- The deploy script uses Helm release labels to discover service names, so it does not depend on hard-coded service names.
- Because wallet-gateway currently serves HTML with `<base href="/">`, Traefik includes an additional `HeaderRegexp` rule to route `/assets` requests to wallet-gateway when the request `Referer` is `/api/wallets`.
- Long-term, the cleaner fix is for wallet-gateway to support a configurable base path (for example `/api/wallets/`) so asset URLs are emitted with that prefix.

## Troubleshooting

If you see `kubernetes cluster unreachable`:

1. Verify tooling:
	- `helm version`
	- `kubectl version --client`
2. Verify active cluster/context:
	- `kubectl config current-context`
	- `kubectl cluster-info`
	- `kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\\n"}'`
3. If you don't have a local cluster running, create one (example):
	- `kind create cluster --name wallet-stack`

If `kind` is not installed, run:

- `make bootstrap-kind`

This installs `kind` and `kubectl` into `~/.local/bin` and creates the `wallet-stack` cluster.