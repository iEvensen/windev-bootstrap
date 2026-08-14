#!/usr/bin/env bash
set -euo pipefail

# Prepare a kubeconfig file that Portainer can import to manage the local k3d cluster.
# This is intentionally separate from Portainer install so Docker GUI setup stays minimal.

KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-dev}"
SA_NAMESPACE="kube-system"
SA_NAME="portainer-k3d-admin"
SA_SECRET_NAME="${SA_NAME}-token"
OUTPUT_KUBECONFIG="${OUTPUT_KUBECONFIG:-$HOME/.kube/portainer-k3d.kubeconfig}"

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as a regular user (sudo is used internally)."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install kubectl first."
  exit 1
fi

if ! kubectl config get-contexts -o name | grep -qx "$KUBE_CONTEXT"; then
  echo "Kubernetes context '$KUBE_CONTEXT' not found."
  echo "Available contexts:"
  kubectl config get-contexts -o name || true
  exit 1
fi

echo "==> Verifying cluster connectivity for context '$KUBE_CONTEXT'"
kubectl --context "$KUBE_CONTEXT" get nodes >/dev/null

echo "==> Creating service account and cluster role binding"
kubectl --context "$KUBE_CONTEXT" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${SA_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}-cluster-admin
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${SA_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
---
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_SECRET_NAME}
  namespace: ${SA_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

for _ in $(seq 1 30); do
  token_b64="$(kubectl --context "$KUBE_CONTEXT" -n "$SA_NAMESPACE" get secret "$SA_SECRET_NAME" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  if [[ -n "$token_b64" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "${token_b64:-}" ]]; then
  echo "Failed to retrieve service account token from secret '$SA_SECRET_NAME'."
  exit 1
fi

token="$(printf '%s' "$token_b64" | base64 -d)"
server="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$KUBE_CONTEXT')].cluster.server}")"
ca_data="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$KUBE_CONTEXT')].cluster.certificate-authority-data}")"

if [[ -z "$server" || -z "$ca_data" ]]; then
  echo "Failed to resolve cluster server or CA data for context '$KUBE_CONTEXT'."
  exit 1
fi

echo "==> Writing kubeconfig for Portainer import"
mkdir -p "$(dirname "$OUTPUT_KUBECONFIG")"
cat > "$OUTPUT_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${KUBE_CONTEXT}
    cluster:
      server: ${server}
      certificate-authority-data: ${ca_data}
users:
  - name: ${SA_NAME}
    user:
      token: ${token}
contexts:
  - name: ${KUBE_CONTEXT}
    context:
      cluster: ${KUBE_CONTEXT}
      user: ${SA_NAME}
current-context: ${KUBE_CONTEXT}
EOF
chmod 600 "$OUTPUT_KUBECONFIG"

echo "==> Done"
echo "Import this kubeconfig in Portainer:"
echo "  Environment wizard -> Kubernetes -> use kubeconfig"
echo "  File: $OUTPUT_KUBECONFIG"
echo
echo "Security note: this grants cluster-admin on the local k3d cluster."
echo "Revoke with:"
echo "  kubectl --context $KUBE_CONTEXT delete clusterrolebinding ${SA_NAME}-cluster-admin"
echo "  kubectl --context $KUBE_CONTEXT -n $SA_NAMESPACE delete sa $SA_NAME secret $SA_SECRET_NAME"