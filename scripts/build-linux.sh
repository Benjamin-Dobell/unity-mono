#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
CONFIGURE_HOST="${CONFIGURE_HOST:-}"
INSTALL=0
INSTALL_DESTDIR="${INSTALL_DESTDIR:-${PREFIX:-}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/}"
DISABLE_MCS="${DISABLE_MCS:-0}"
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick)
      INSTALL=0
      shift
      ;;
    --full)
      INSTALL=1
      if [[ -z "${INSTALL_DESTDIR}" ]]; then
        INSTALL_DESTDIR="${REPO_ROOT}/tmp-linux"
      fi
      shift
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --install)
      INSTALL=1
      INSTALL_DESTDIR="$2"
      shift 2
      ;;
    --install-prefix)
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    --prefix)
      INSTALL_PREFIX="$2"
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
  echo "  INSTALL_DESTDIR=${INSTALL_DESTDIR}"
  echo "  INSTALL_PREFIX=${INSTALL_PREFIX}"
fi
echo "  DISABLE_MCS=${DISABLE_MCS}"
echo "  CLEAN=${CLEAN}"
if [[ -n "${CONFIGURE_HOST}" ]]; then
  echo "  CONFIGURE_HOST=${CONFIGURE_HOST}"
else
  echo "  CONFIGURE_HOST=<not set>"
fi

if [[ "${INSTALL}" == "1" && -z "${INSTALL_DESTDIR}" ]]; then
  echo "Missing install directory. Use --install <destdir>." >&2
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

if [[ "${DISABLE_MCS}" == "1" ]]; then
  AUTOGEN_ARGS+=(--disable-mcs-build)
fi

if [[ "${INSTALL}" == "1" ]]; then
  AUTOGEN_ARGS+=(--prefix="${INSTALL_PREFIX}")
fi

if [[ -n "${CONFIGURE_HOST}" ]]; then
  AUTOGEN_ARGS+=(--host="${CONFIGURE_HOST}")
fi

./autogen.sh "${AUTOGEN_ARGS[@]}"

if [[ "${INSTALL}" == "1" ]]; then
  make -j"${JOBS}"
  make install DESTDIR="${INSTALL_DESTDIR}"

  # Linux Unity Mono probes corlib under net_4_x-linux. Upstream install layout
  # places these assemblies in 4.5, so add a compatibility profile link.
  install_prefix_normalized="${INSTALL_PREFIX%/}"
  if [[ -z "${install_prefix_normalized}" ]]; then
    install_prefix_normalized="/"
  fi
  if [[ "${install_prefix_normalized}" == "/" ]]; then
    install_root="${INSTALL_DESTDIR}"
  else
    install_root="${INSTALL_DESTDIR}${install_prefix_normalized}"
  fi

  mono_lib_dir="${install_root}/lib/mono"
  if [[ -d "${mono_lib_dir}/4.5" && ! -e "${mono_lib_dir}/net_4_x-linux" ]]; then
    ln -s 4.5 "${mono_lib_dir}/net_4_x-linux"
  fi

  # Some managed components P/Invoke System.Native directly.
  # Provide compatibility soname links to mono-native for environments
  # where dllmap resolution is not applied.
  for native_lib_dir in "${install_root}/lib" "${install_root}/usr/lib"; do
    if [[ -e "${native_lib_dir}/libmono-native.so" ]]; then
      if [[ ! -e "${native_lib_dir}/libSystem.Native.so" ]]; then
        ln -s libmono-native.so "${native_lib_dir}/libSystem.Native.so"
      fi
      if [[ ! -e "${native_lib_dir}/libSystem.Net.Security.Native.so" ]]; then
        ln -s libmono-native.so "${native_lib_dir}/libSystem.Net.Security.Native.so"
      fi
    fi
  done

  if [[ "${DISABLE_MCS}" != "1" ]]; then
    if [[ ! -f "${install_root}/lib/mono/net_4_x-linux/mscorlib.dll" ]]; then
      echo "ERROR: Missing ${install_root}/lib/mono/net_4_x-linux/mscorlib.dll" >&2
      echo "The produced runtime is incomplete for Linux xbuild/mcs execution." >&2
      exit 3
    fi
  fi

  if [[ ! -f "${install_root}/bin/xbuild" ]]; then
    echo "ERROR: Missing ${install_root}/bin/xbuild" >&2
    exit 3
  fi

  echo "Full build + install complete."
  echo "Install prefix: ${INSTALL_PREFIX}"
  echo "Staged to: ${INSTALL_DESTDIR}"
else
  make -j"${JOBS}" -C mono
  echo "Build complete (no install)."
fi
