#!/usr/bin/env bash
set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$SKILL_ROOT/scripts"
BIN_DIR="$SKILL_ROOT/bin"
CACHE_DIR="${GOCACHE:-/tmp/db-query-go-build-cache}"

mkdir -p "$BIN_DIR"
mkdir -p "$CACHE_DIR"

echo "[build] source: $SRC_DIR"
echo "[build] output: $BIN_DIR"
echo "[build] gocache: $CACHE_DIR"

cd "$SRC_DIR"

export GOCACHE="$CACHE_DIR"
export GOFLAGS="${GOFLAGS:-} -mod=readonly"

echo "[build] build linux amd64"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o "$BIN_DIR/db-query-linux-amd64" ./cmd/db_query

echo "[build] build windows amd64"
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -o "$BIN_DIR/db-query-windows-amd64.exe" ./cmd/db_query

chmod +x "$BIN_DIR/db-query-linux-amd64"

echo "[build] done"
echo "  - $BIN_DIR/db-query-linux-amd64"
echo "  - $BIN_DIR/db-query-windows-amd64.exe"
