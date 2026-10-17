#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export TEST_LOG="$TEST_DIR/commands"
export DEPLOYMENT_CREATED="$TEST_DIR/deployment-created"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

k3d() {
  printf 'k3d %s\n' "$*" >> "$TEST_LOG"
  if [ "$*" == 'cluster list' ] && [ "$EXISTING_CLUSTER" == true ]; then
    printf 'dev 1/1 2/2 true\n'
  fi
  return 0
}

kubectl() {
  printf 'kubectl %s\n' "$*" >> "$TEST_LOG"
  case "$1" in
    apply) return 0 ;;
    wait)
      [ "$*" == 'wait --for=create deployment/traefik -n kube-system --timeout=180s' ] || return 2
      [ "${FAIL_WAIT:-false}" != true ] || return 42
      touch "$DEPLOYMENT_CREATED"
      ;;
    rollout)
      [ -f "$DEPLOYMENT_CREATED" ] || return 3
      [ "$*" == 'rollout status deploy/traefik -n kube-system --timeout=120s' ] || return 4
      ;;
    *) return 5 ;;
  esac
}
export -f k3d kubectl

for EXISTING_CLUSTER in false true; do
  export EXISTING_CLUSTER
  rm -f "$TEST_LOG" "$DEPLOYMENT_CREATED"
  bash "$REPO_ROOT/wsl/k3d/create-cluster.sh" >/dev/null
  grep -q '^kubectl rollout status' "$TEST_LOG" || fail "rollout was not checked"
  if [ "$EXISTING_CLUSTER" == false ]; then
    grep -q '^k3d cluster create --config ' "$TEST_LOG" || fail "cluster not created"
  elif grep -q '^k3d cluster create ' "$TEST_LOG"; then
    fail "existing cluster recreated"
  fi
  printf 'PASS creation wait precedes rollout (existing-cluster=%s)\n' "$EXISTING_CLUSTER"
done

export FAIL_WAIT=true
rm -f "$TEST_LOG" "$DEPLOYMENT_CREATED"
if bash "$REPO_ROOT/wsl/k3d/create-cluster.sh" >/dev/null; then
  fail "creation timeout reported success"
else
  [ "$?" -eq 42 ] || fail "creation failure exit status not preserved"
fi
if grep -q '^kubectl rollout status' "$TEST_LOG"; then
  fail "rollout attempted after creation timeout"
fi
bash -n "$REPO_ROOT/wsl/k3d/create-cluster.sh"
printf 'PASS creation failure stops setup before rollout\n'