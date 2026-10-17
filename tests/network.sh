#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/lib/network.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export TMPDIR="$TEST_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

curl() {
  local output_file=""
  local arguments=" $* "
  [[ "$arguments" == *' --retry 3 '* ]] || fail "missing curl retries"
  [[ "$arguments" == *' --retry-all-errors '* ]] || fail "missing connection-error retries"
  [[ "$arguments" == *' --connect-timeout 15 '* ]] || fail "missing connection timeout"
  [[ "$arguments" == *' --max-time 120 '* ]] || fail "missing transfer timeout"
  [[ "$arguments" == *' --retry-max-time 180 '* ]] || fail "missing retry budget"
  [[ "$arguments" == *' --fail '* ]] || fail "missing HTTP failure handling"
  while [ "$#" -gt 0 ]; do
    if [ "$1" == --output ]; then
      output_file="$2"
      shift
    fi
    shift
  done
  [ -n "$output_file" ] || fail "download must use a temporary file"
  printf '%s' "$output_file" > "$TEST_DIR/last-download"
  if [ "${FAIL_DOWNLOAD:-false}" == true ]; then
    printf 'partial response' > "$output_file"
    return 7
  fi
  printf 'complete response' > "$output_file"
}

[ "$(download https://example.invalid/file)" == 'complete response' ] || fail "stdout download"
[ ! -e "$(cat "$TEST_DIR/last-download")" ] || fail "temporary file leaked after success"
download https://example.invalid/file "$TEST_DIR/result"
[ "$(cat "$TEST_DIR/result")" == 'complete response' ] || fail "file download"

export FAIL_DOWNLOAD=true
if output="$(download https://example.invalid/file)"; then
  fail "failed download reported success"
else
  [ "$?" -eq 7 ] || fail "download exit status not preserved"
fi
[ -z "$output" ] || fail "partial download reached stdout"
if download https://example.invalid/file "$TEST_DIR/result"; then
  fail "failed file download reported success"
fi
[ "$(cat "$TEST_DIR/result")" == 'complete response' ] || fail "failed download overwrote destination"
[ ! -e "$(cat "$TEST_DIR/last-download")" ] || fail "temporary file leaked after failure"
unset FAIL_DOWNLOAD
printf 'PASS buffered downloads, failure propagation, and cleanup\n'

unset -f curl
[ "$(download "file://$TEST_DIR/result")" == 'complete response' ] || fail "real curl download"
download "file://$TEST_DIR/result" "$TEST_DIR/copied-result"
cmp "$TEST_DIR/result" "$TEST_DIR/copied-result" || fail "real curl file output"
printf 'PASS real curl options and buffered output\n'

sudo() { printf '%s\n' "$@"; }
output="$(apt_get update)"
[[ "$output" == *'Acquire::Retries=3'* ]] || fail "missing apt retries"
[[ "$output" == *'Acquire::http::Timeout=30'* ]] || fail "missing HTTP timeout"
[[ "$output" == *'Acquire::https::Timeout=30'* ]] || fail "missing HTTPS timeout"
[[ "$output" == *'APT::Update::Error-Mode=any'* ]] || fail "missing strict apt update"
[[ "$output" == *$'\nupdate' ]] || fail "apt arguments not forwarded"
output="$(apt_get install -y curl)"
[[ "$output" == *$'\ninstall\n-y\ncurl' ]] || fail "apt install arguments not forwarded"
sudo() { return 42; }
if apt_get update; then
  fail "apt failure reported success"
else
  [ "$?" -eq 42 ] || fail "apt exit status not preserved"
fi
printf 'PASS apt options, arguments, and failure propagation\n'

attempts=0
delays=0
sleep() { delays=$((delays + 1)); }
flaky_download() {
  attempts=$((attempts + 1))
  [ "$attempts" -ge 3 ]
}
retry_download flaky_download 2>/dev/null
[ "$attempts" -eq 3 ] || fail "did not stop after success"
[ "$delays" -eq 2 ] || fail "incorrect retry delays"
attempts=0
delays=0
failed_download() {
  attempts=$((attempts + 1))
  return 37
}
if retry_download failed_download 2>/dev/null; then
  fail "exhausted retries reported success"
else
  [ "$?" -eq 37 ] || fail "final exit status not preserved"
fi
[ "$attempts" -eq 4 ] || fail "incorrect attempt limit"
[ "$delays" -eq 3 ] || fail "delay after final attempt"
printf 'PASS bounded retries, early success, and final failure\n'

for script in \
  lib/network.sh \
  wsl/install.sh \
  wsl/ubuntu-setup.sh \
  github/setup-github.sh \
  wsl/docker/install-portainer.sh; do
  bash -n "$REPO_ROOT/$script"
done
printf 'PASS Bash syntax for all updated setup scripts\n'

for example in dotnet typescript; do
  dockerfile="$REPO_ROOT/devcontainer/examples/$example/.devcontainer/Dockerfile"
  run_commands="$(awk '
    /^RUN / { active = 1; sub(/^RUN /, "") }
    active {
      continued = sub(/\\$/, "")
      if (continued) {
        printf "%s ", $0
      } else {
        print
        active = 0
      }
    }
  ' "$dockerfile")"
  sh -n <<< "$run_commands"
  (
    attempts=0
    delays=0
    sudo() {
      if [ "$1" == apt-get ]; then
        [[ " $* " == *' Acquire::Retries=3 '* ]] || fail "devcontainer apt retries"
        [[ " $* " == *' Acquire::http::Timeout=30 '* ]] || fail "devcontainer HTTP timeout"
        [[ " $* " == *' Acquire::https::Timeout=30 '* ]] || fail "devcontainer HTTPS timeout"
        if [[ " $* " == *' update '* ]]; then
          [[ " $* " == *' APT::Update::Error-Mode=any '* ]] || fail "devcontainer strict update"
        fi
      fi
      return 0
    }
    git() {
      attempts=$((attempts + 1))
      [ "$((attempts % 3))" -eq 0 ]
    }
    eval "$run_commands" 2>/dev/null
    [ "$attempts" -eq 12 ] || fail "devcontainer clone retries"
    [ "$delays" -eq 8 ] || fail "devcontainer clone delays"
    attempts=0
    delays=0
    git() { attempts=$((attempts + 1)); return 37; }
    if eval "$run_commands" 2>/dev/null; then
      fail "devcontainer ignored clone failure"
    fi
    [ "$attempts" -eq 4 ] || fail "devcontainer attempt limit"
    [ "$delays" -eq 3 ] || fail "devcontainer final delay"
  )
  printf 'PASS %s devcontainer RUN syntax, apt policy, and clone retries\n' "$example"
done