#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
CONFIGURE_HOST="${CONFIGURE_HOST:-}"
INSTALL=0
PREFIX="${PREFIX:-}"
CLEAN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      INSTALL=0
      shift
      ;;
    --full)
      INSTALL=1
      if [[ -z "${PREFIX}" ]]; then
        PREFIX="${REPO_ROOT}/tmp-linux"
      fi
      shift
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --install)
      INSTALL=1
      PREFIX="$2"
      shift 2
      ;;
    --prefix)
      INSTALL=1
      PREFIX="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --no-clean)
      CLEAN=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script must be run on Linux." >&2
  exit 1
fi

cd "${REPO_ROOT}"

export CFLAGS="${CFLAGS:--fPIC -Os}"
export CXXFLAGS="${CXXFLAGS:-${CFLAGS}}"
export CPPFLAGS="${CPPFLAGS:-${CFLAGS}}"

detect_host_triple() {
  case "$(uname -m)" in
    x86_64)
      echo "x86_64-pc-linux-gnu"
      ;;
    aarch64|arm64)
      echo "aarch64-unknown-linux-gnu"
      ;;
    armv7l)
      echo "armv7-unknown-linux-gnueabihf"
      ;;
    *)
      echo ""
      ;;
  esac
}

if [[ -z "${CONFIGURE_HOST}" ]]; then
  CONFIGURE_HOST="$(detect_host_triple)"
fi

echo "Building Unity Mono (Linux)"
echo "  JOBS=${JOBS}"
echo "  INSTALL=${INSTALL}"
if [[ "${INSTALL}" == "1" ]]; then
  echo "  PREFIX=${PREFIX}"
fi
echo "  CLEAN=${CLEAN}"
if [[ -n "${CONFIGURE_HOST}" ]]; then
  echo "  CONFIGURE_HOST=${CONFIGURE_HOST}"
else
  echo "  CONFIGURE_HOST=<not set>"
fi

if [[ "${INSTALL}" == "1" && -z "${PREFIX}" ]]; then
  echo "Missing install prefix. Use --install <prefix>." >&2
  exit 2
fi

if [[ "${CLEAN}" == "1" ]]; then
  if [[ -f Makefile ]]; then
    make distclean >/dev/null 2>&1 || true
  fi
  # Remove stale host-specific artifacts from prior builds (for example Mach-O objects).
  find mono -type d -name .libs -prune -exec rm -rf {} +
  find mono -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '*.a' \) -delete
fi

AUTOGEN_ARGS=(
  --disable-mcs-build \
  --with-glib=embedded \
  --disable-nls \
  --with-mcs-docs=no \
  --enable-no-threads-discovery=yes \
  --enable-ignore-dynamic-loading=yes \
  --enable-dont-register-main-static-data=yes \
  --enable-thread-local-alloc=no \
  --enable-unity-define=yes \
  --with-monotouch=no \
  --disable-parallel-mark \
  --enable-minimal=com,shared_perfcounters \
  --enable-verify-defines
)

if [[ "${INSTALL}" == "1" ]]; then
  AUTOGEN_ARGS+=(--prefix="${PREFIX}")
fi

if [[ -n "${CONFIGURE_HOST}" ]]; then
  AUTOGEN_ARGS+=(--host="${CONFIGURE_HOST}")
fi

./autogen.sh "${AUTOGEN_ARGS[@]}"

if [[ "${INSTALL}" == "1" ]]; then
  make -j"${JOBS}"
  make install
  echo "Full build + install complete."
  echo "Installed prefix: ${PREFIX}"
else
  make -j"${JOBS}" -C mono
  echo "Build complete (no install)."
fi
