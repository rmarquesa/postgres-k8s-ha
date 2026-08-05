#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

"$ROOT/scripts/install-operators.sh"
"$ROOT/scripts/install-longhorn.sh"
"$ROOT/scripts/install-minio.sh"
"$ROOT/scripts/install-database.sh"
