#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/tools/docker/mono-linux-build.Dockerfile"
IMAGE_TAG="${IMAGE_TAG:-unity-mono-linux-build:local}"
QUICK=1
INSTALL_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      QUICK=0
      shift
      ;;
    --quick)
      QUICK=1
      shift
      ;;
    --install)
      QUICK=0
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found in PATH" >&2
  exit 1
fi

cd "${REPO_ROOT}"

echo "Building docker image: ${IMAGE_TAG}"
docker build -f "${DOCKERFILE}" -t "${IMAGE_TAG}" .

BUILD_CMD=(./scripts/build-linux.sh --jobs 4)
if [[ "${QUICK}" == "1" ]]; then
  BUILD_CMD+=(--quick)
else
  if [[ -z "${INSTALL_PREFIX}" ]]; then
    INSTALL_PREFIX="/workspace/tmp-linux"
  fi
  BUILD_CMD+=(--install "${INSTALL_PREFIX}")
fi

echo "Running Linux build in docker (${BUILD_CMD[*]})"
docker run --rm \
  -v "${REPO_ROOT}:/workspace" \
  -w /workspace \
  "${IMAGE_TAG}" \
  "${BUILD_CMD[@]}"

echo "Docker Linux build completed."
