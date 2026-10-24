#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: kingD2N
# SPDX-License-Identifier: Apache-2.0
#
# Build the kernel Image from source (kingD2N/Tree_ingres, branch melt-ingres)
# and install it into the AOSPA prebuilt kernel dir (KERNEL_PREBUILT_DIR),
# replacing the prebuilt Image + System.map. DTB/DTBO and vendor modules stay
# the ones already in KERNEL_PREBUILT_DIR (LineageOS 23.2 ingres); the new Image
# is only installed when its symbol CRCs match every one of those modules.
#
# Run from the root of the ROM source tree, before building the ROM:
#
#   device/xiaomi/sm8450-common/kernel/build-kernel.sh [device]
#   ./rom-build.sh ingres
#
# Environment overrides:
#   KERNEL_SRC          kernel source       (default: kernel/xiaomi/sm8450)
#   KERNEL_PREBUILT_DIR AOSPA prebuilt dir  (default: device/xiaomi/<device>-kernel)
#   KERNEL_OBJ          build output dir    (default: out/kernel-<device>)
#   KERNEL_FRAGMENTS    config fragments    (default: same set as the Melt-MIX CI)
#   CLANG_DIR           clang bin dir       (default: newest prebuilts/clang/host/linux-x86/clang-r*)
#   JOBS                parallel jobs       (default: nproc)
#   SKIP_CRC_CHECK=1    install even if the module CRC check fails (not recommended)

set -euo pipefail

DEVICE="${1:-${TARGET_DEVICE:-ingres}}"
TOP="$(pwd)"

KERNEL_SRC="${KERNEL_SRC:-kernel/xiaomi/sm8450}"
KERNEL_PREBUILT_DIR="${KERNEL_PREBUILT_DIR:-device/xiaomi/${DEVICE}-kernel}"
KERNEL_OBJ="${KERNEL_OBJ:-out/kernel-${DEVICE}}"
KERNEL_FRAGMENTS="${KERNEL_FRAGMENTS:-vendor/waipio_GKI.config vendor/xiaomi_GKI.config vendor/${DEVICE}_GKI.config vendor/debugfs.config}"
JOBS="${JOBS:-$(nproc)}"

log() { echo -e "\033[1;34m[build-kernel]\033[0m $*"; }
die() { echo -e "\033[1;31m[build-kernel]\033[0m $*" >&2; exit "${2:-1}"; }

abs() { case "$1" in /*) echo "$1" ;; *) echo "${TOP}/$1" ;; esac; }
KERNEL_SRC="$(abs "$KERNEL_SRC")"
KERNEL_PREBUILT_DIR="$(abs "$KERNEL_PREBUILT_DIR")"
KERNEL_OBJ="$(abs "$KERNEL_OBJ")"

[ -f "${KERNEL_SRC}/Makefile" ] || die "kernel source not found at ${KERNEL_SRC}
  sync it first, e.g. with device/xiaomi/sm8450-common/kernel/local_manifest.xml"
[ -d "${KERNEL_PREBUILT_DIR}" ] || die "prebuilt kernel dir not found: ${KERNEL_PREBUILT_DIR}"
[ -f "${KERNEL_SRC}/arch/arm64/configs/vendor/${DEVICE}_GKI.config" ] \
    || die "no vendor/${DEVICE}_GKI.config in ${KERNEL_SRC} - wrong branch? (expected melt-ingres)"

# Toolchain: newest AOSP clang in the ROM tree, else whatever clang is on PATH.
if [ -z "${CLANG_DIR:-}" ]; then
    CLANG_DIR="$(ls -d "${TOP}"/prebuilts/clang/host/linux-x86/clang-r*/bin 2>/dev/null | sort -V | tail -n1 || true)"
fi
if [ -n "${CLANG_DIR:-}" ]; then
    export PATH="${CLANG_DIR}:${PATH}"
fi
missing=()
for t in make bc bison flex cpio perl python3 xz; do
    command -v "$t" >/dev/null || missing+=("$t")
done
[ "${#missing[@]}" -eq 0 ] || die "missing host tools: ${missing[*]} (e.g. apt install bc bison flex cpio perl python3 xz-utils)"
command -v clang >/dev/null || die "clang not found (set CLANG_DIR)"
command -v ld.lld >/dev/null || die "ld.lld not found (set CLANG_DIR)"
log "clang: $(clang --version | head -n1)"

MAKE_ARGS=(-C "${KERNEL_SRC}" O="${KERNEL_OBJ}" ARCH=arm64 LLVM=1 LLVM_IAS=1
           CC=clang LD=ld.lld HOSTCC=clang HOSTCXX=clang++)

# 1) config (same fragments as the Melt-MIX kernel CI)
log "source: ${KERNEL_SRC} ($(git -C "${KERNEL_SRC}" rev-parse --short HEAD 2>/dev/null || echo no-git))"
log "config: gki_defconfig ${KERNEL_FRAGMENTS}"
mkdir -p "${KERNEL_OBJ}"
# shellcheck disable=SC2086
make "${MAKE_ARGS[@]}" gki_defconfig ${KERNEL_FRAGMENTS}

# 2) Image
log "building Image with ${JOBS} jobs"
make "${MAKE_ARGS[@]}" -j"${JOBS}" Image

IMG="${KERNEL_OBJ}/arch/arm64/boot/Image"
MAP="${KERNEL_OBJ}/System.map"
[ -f "${IMG}" ] && [ -f "${MAP}" ] || die "build finished without Image/System.map"
log "built: $(strings "${IMG}" | grep -m1 '^Linux version 5' | cut -d' ' -f1-3)"

# 3) CRC check against the prebuilt vendor modules
CRC_TOOL="${KERNEL_PREBUILT_DIR}/tools/crccheck.py"
MOD_DIRS=()
for d in vendor_ramdisk vendor_dlkm system_dlkm; do
    [ -d "${KERNEL_PREBUILT_DIR}/${d}" ] && MOD_DIRS+=("${KERNEL_PREBUILT_DIR}/${d}")
done
if [ "${SKIP_CRC_CHECK:-0}" = 1 ]; then
    log "SKIP_CRC_CHECK=1 - module CRC check skipped"
elif [ ! -f "${CRC_TOOL}" ] || [ "${#MOD_DIRS[@]}" -eq 0 ]; then
    log "no crccheck.py or module dirs in ${KERNEL_PREBUILT_DIR} - CRC check skipped"
else
    log "checking symbol CRCs against the modules in: ${MOD_DIRS[*]}"
    if ! python3 -I "${CRC_TOOL}" "${IMG}" "${MAP}" "${MOD_DIRS[@]}" | tee "${KERNEL_OBJ}/crc.log" \
        || ! grep -q "RESULT: OK" "${KERNEL_OBJ}/crc.log"; then
        die "CRC mismatch with the prebuilt modules - Image NOT installed (see ${KERNEL_OBJ}/crc.log)" 3
    fi
fi

# 4) install (keep the previous Image as Image.prebuilt for a quick rollback)
if [ -f "${KERNEL_PREBUILT_DIR}/Image" ] && [ ! -f "${KERNEL_PREBUILT_DIR}/Image.prebuilt" ]; then
    cp "${KERNEL_PREBUILT_DIR}/Image" "${KERNEL_PREBUILT_DIR}/Image.prebuilt"
    cp "${KERNEL_PREBUILT_DIR}/System.map" "${KERNEL_PREBUILT_DIR}/System.map.prebuilt" 2>/dev/null || true
fi
cp "${IMG}" "${KERNEL_PREBUILT_DIR}/Image"
cp "${MAP}" "${KERNEL_PREBUILT_DIR}/System.map"
git -C "${KERNEL_SRC}" rev-parse HEAD > "${KERNEL_PREBUILT_DIR}/Image.source" 2>/dev/null || true

log "installed into ${KERNEL_PREBUILT_DIR} - now build the ROM as usual"
log "rollback: mv Image.prebuilt Image && mv System.map.prebuilt System.map (in ${KERNEL_PREBUILT_DIR})"
