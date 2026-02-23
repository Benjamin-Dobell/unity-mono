#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATCH_FILE="${REPO_ROOT}/scripts/patches/macos-arm64-build.patch"

CLEAN="${CLEAN:-0}"
ARTIFACT="${ARTIFACT:-1}"
DISABLE_MCS="${DISABLE_MCS:-1}"
STEVEDORE_BUILD_DEPS="${STEVEDORE_BUILD_DEPS:-1}"
BUILD_DEPS_DIR="${BUILD_DEPS_DIR:-external/buildscripts/artifacts/Stevedore}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/builds/macos-arm64}"
KEEP_WORKTREE="${KEEP_WORKTREE:-0}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required." >&2
  exit 1
fi

if [[ ! -f "${PATCH_FILE}" ]]; then
  echo "Missing patch file: ${PATCH_FILE}" >&2
  exit 1
fi

cd "${REPO_ROOT}"

HEAD_COMMIT="$(git rev-parse HEAD)"
WORKTREE_ROOT="${REPO_ROOT}/.build-tmp"
WORKTREE_DIR="${WORKTREE_ROOT}/macos-arm64-${HEAD_COMMIT:0:12}-$$"

mkdir -p "${WORKTREE_ROOT}" "${OUTPUT_DIR}"
git worktree add --detach "${WORKTREE_DIR}" "${HEAD_COMMIT}" >/dev/null

cleanup() {
  if [[ "${KEEP_WORKTREE}" == "1" ]]; then
    echo "Keeping worktree: ${WORKTREE_DIR}"
  else
    git worktree remove --force "${WORKTREE_DIR}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

git -C "${WORKTREE_DIR}" apply --whitespace=nowarn "${PATCH_FILE}"

echo "Building Unity Mono (macOS arm64)"
echo "  WORKTREE_DIR=${WORKTREE_DIR}"
echo "  PATCH_FILE=${PATCH_FILE}"
echo "  CLEAN=${CLEAN}"
echo "  ARTIFACT=${ARTIFACT}"
echo "  DISABLE_MCS=${DISABLE_MCS}"
echo "  STEVEDORE_BUILD_DEPS=${STEVEDORE_BUILD_DEPS}"
echo "  BUILD_DEPS_DIR=${BUILD_DEPS_DIR}"
echo "  OUTPUT_DIR=${OUTPUT_DIR}"

cd "${WORKTREE_DIR}"

perl external/buildscripts/build.pl \
  --build=1 \
  --clean="${CLEAN}" \
  --artifact="${ARTIFACT}" \
  --classlibtests=0 \
  --disablemcs="${DISABLE_MCS}" \
  --targetarch=arm64 \
  --stevedorebuilddeps="${STEVEDORE_BUILD_DEPS}" \
  --builddeps="${BUILD_DEPS_DIR}"

mkdir -p "${OUTPUT_DIR}/embedruntimes" "${OUTPUT_DIR}/monodistribution"
rm -rf "${OUTPUT_DIR}/embedruntimes/osx-tmp-arm64" "${OUTPUT_DIR}/monodistribution/bin-osx-tmp-arm64"
cp -R "${WORKTREE_DIR}/builds/embedruntimes/osx-tmp-arm64" "${OUTPUT_DIR}/embedruntimes/"
cp -R "${WORKTREE_DIR}/builds/monodistribution/bin-osx-tmp-arm64" "${OUTPUT_DIR}/monodistribution/"

echo
echo "Build complete. Key artifacts:"
echo "  ${OUTPUT_DIR}/embedruntimes/osx-tmp-arm64/libmonobdwgc-2.0.dylib"
echo "  ${OUTPUT_DIR}/embedruntimes/osx-tmp-arm64/libmonosgen-2.0.dylib"
echo "  ${OUTPUT_DIR}/monodistribution/bin-osx-tmp-arm64/mono"
