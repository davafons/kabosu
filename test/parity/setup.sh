#!/usr/bin/env bash
# Create the SudachiPy virtualenv used by the parity suite. SudachiPy is the
# official Python binding to the same sudachi.rs core kabosu wraps, so it is the
# natural reference for "how close are the bindings". Pinned to match the
# sudachi.rs tag in ext/kabosu/Cargo.toml.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/venv"
SUDACHIPY_VERSION="${SUDACHIPY_VERSION:-0.6.11}"

python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet "sudachipy==$SUDACHIPY_VERSION"
"$VENV/bin/python" -c "import sudachipy; print('sudachipy', sudachipy.__version__, 'ready')"
