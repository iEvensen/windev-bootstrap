#!/usr/bin/env bash

download() (
  set -euo pipefail
  local url="$1"
  local destination="${2:-}"
  local temporary_file
  temporary_file="$(mktemp)"
  trap 'rm -f "$temporary_file"' EXIT

  curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --connect-timeout 15 --max-time 120 --retry-max-time 180 \
    --output "$temporary_file" "$url" || return "$?"

  if [ -n "$destination" ]; then
    mv -f "$temporary_file" "$destination"
  else
    cat "$temporary_file"
  fi
)

apt_get() {
  sudo apt-get \
    -o Acquire::Retries=3 \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    -o APT::Update::Error-Mode=any \
    "$@"
}

retry_download() {
  local attempt
  local status=0
  for attempt in 1 2 3 4; do
    if "$@"; then
      return 0
    else
      status=$?
    fi
    if [ "$attempt" -lt 4 ]; then
      printf 'Download command failed (exit %s); retrying (%s/3)...\n' "$status" "$attempt" >&2
      sleep 2
    fi
  done
  return "$status"
}