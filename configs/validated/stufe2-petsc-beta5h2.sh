#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Heiko Gleu
# Plan I build script — see https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70
# This script invokes (does not redistribute) third-party software. See NOTICE.md.

# Stufe 2: PETSc 3.25.1 + Hypre BoomerAMG SYCL + Kokkos + Umpire.
# Lauft in `bash --noprofile --norc`. Vorab via pkexec: opencl-headers + ocl-icd-opencl-dev.
# xpu-smi durch intel_gpu_top ersetzt (Ubuntu 26.04 hat kein xpu-smi-Paket).

set -o pipefail   # KEIN -u (Stufe-1-Lehre, ESI bashrc:184)

# Defensive unset: Foundation v13 oder alte Sessions
unset WM_PROJECT_DIR FOAM_INST_DIR WM_PROJECT WM_PROJECT_VERSION WM_PROJECT_INST_DIR
unset WM_THIRD_PARTY_DIR WM_OPTIONS WM_COMPILER WM_COMPILE_OPTION
unset FOAM_APP FOAM_APPBIN FOAM_LIBBIN FOAM_TUTORIALS FOAM_RUN
unset FOAM_USER_APPBIN FOAM_USER_LIBBIN
unset PETSC_DIR PETSC_ARCH

INSTALL_ROOT=/opt/openfoam-v2512
PETSC_VER=3.25.1
PETSC_TARBALL=petsc-${PETSC_VER}.tar.gz
PETSC_URL=https://web.cels.anl.gov/projects/petsc/download/release-snapshots/${PETSC_TARBALL}
PETSC_URL_ALT=https://ftp.mcs.anl.gov/pub/petsc/release-snapshots/${PETSC_TARBALL}
PETSC_DIR_ROOT=${INSTALL_ROOT}/petsc-${PETSC_VER}
PETSC_ARCH=arch-bmg-opt
# Plan H: prefer oneAPI 2025.3.x (PMZFX/Aurora-validated for B70) over 2026.x
# Reason: icpx 2026 + DPCT 2025.3 incompatible; KokkosKernels/Hypre stable on 2025.3
ONEAPI_SETVARS=
for cand in \
  /opt/intel/oneapi/2025.3/setvars.sh \
  /opt/intel/oneapi/2025.3/oneapi-vars.sh \
  /opt/intel/oneapi/2025.3.*/setvars.sh \
  /opt/intel/oneapi/2025.*/setvars.sh \
  /opt/intel/oneapi/setvars.sh \
  /opt/intel/oneapi/2026.*/setvars.sh; do
  for f in $cand; do
    if [[ -f "$f" ]]; then ONEAPI_SETVARS="$f"; break 2; fi
  done
done
[[ -n "$ONEAPI_SETVARS" ]] || { echo "FEHLER: oneAPI setvars.sh nicht gefunden"; exit 1; }
echo "oneAPI selected: $ONEAPI_SETVARS"

SUDO_MODE="pkexec-prep (vorab, 1 GUI-Auth)"
APT_INSTALLED_COUNT=2  # opencl-headers + ocl-icd-opencl-dev
GPU_MON_TOOL="intel_gpu_top (xpu-smi nicht in U26.04-Repos)"

###############################################
# Phase 1 - ENV-Setup (apt schon erledigt vorab)
###############################################
echo "=== Phase 1: ENV (ESI + oneAPI in einer Shell) ==="

[[ -f "$INSTALL_ROOT/OpenFOAM-v2512/etc/bashrc" ]] || { echo "FEHLER: ESI v2512 fehlt"; exit 1; }
[[ -f "$ONEAPI_SETVARS" ]] || { echo "FEHLER: oneAPI setvars.sh fehlt"; exit 1; }

# 1a. ESI v2512 sourcen
export FOAM_INST_DIR=$INSTALL_ROOT
source "$INSTALL_ROOT/OpenFOAM-v2512/etc/bashrc" \
  WM_COMPILER=Gcc WM_LABEL_SIZE=32 WM_PRECISION_OPTION=DP WM_COMPILE_OPTION=Opt
[[ "${WM_PROJECT_DIR:-}" == "$INSTALL_ROOT/OpenFOAM-v2512" ]] \
  || { echo "FEHLER: ESI-source fehlgeschlagen"; exit 1; }

# 1b. oneAPI sourcen (nach ESI - Reihenfolge wichtig)
source "$ONEAPI_SETVARS" --force >/tmp/stufe2-oneapi-source.log 2>&1
echo "oneAPI sourced; tail:"; tail -3 /tmp/stufe2-oneapi-source.log

# 1b'. PATH-fix: oneAPI prepended Intel-MPI; ESI v2512 was built with sys-openmpi.
# Force /usr/bin first so 'mpicc' resolves to System-OpenMPI for PETSc-foam parity.
export PATH=/usr/bin:$PATH

# 1b''. OMPI wrapper override: System-OpenMPI mpicc/mpicxx call icx/icpx underneath.
export OMPI_CC=icx
export OMPI_CXX=icpx

# 1c. Verifikation
echo "--- ENV check ---"
echo "WM_PROJECT_DIR:  $WM_PROJECT_DIR"
echo "ONEAPI_ROOT:     ${ONEAPI_ROOT:-<unset>}"
echo "MKLROOT:         ${MKLROOT:-<unset>}"
[[ -n "${MKLROOT:-}" ]] || { echo "FEHLER: MKLROOT leer"; exit 1; }

# mpicc must be System-OpenMPI (path-based check, version-string is unreliable)
echo "--- mpicc ---"
which mpicc
mpicc -show 2>&1 | head -1 || true
if ! mpicc -show 2>/dev/null | grep -q "openmpi"; then
  echo "FEHLER: mpicc nicht System-OpenMPI - PATH/setup falsch"
  echo "mpicc -show: $(mpicc -show 2>&1 | head -1)"
  exit 1
fi
echo "OMPI_CC=$OMPI_CC, mpicc effectively calls: $(OMPI_CC=icx mpicc --version 2>&1 | head -1)"

# icpx
echo "--- icpx ---"
which icpx
icpx --version 2>&1 | head -1

# sycl-ls B70 detection
echo "--- sycl-ls ---"
sycl-ls 2>&1 | tee /tmp/stufe2-sycl-ls.txt
if ! grep -qE "0xe223|Battlemage" /tmp/stufe2-sycl-ls.txt; then
  echo "FEHLER: B70 nicht in sycl-ls erkannt"
  exit 1
fi
echo "B70 (0xe223) erkannt."

# intel_gpu_top sanity (statt xpu-smi)
echo "--- intel_gpu_top -L (list devices) ---"
intel_gpu_top -L 2>&1 | head -10 || echo "WARNUNG: intel_gpu_top -L"

echo "Phase 1 OK."
echo ""

###############################################
# Phase 2 - PETSc Source
###############################################
echo "=== Phase 2: PETSc Source ==="
mkdir -p "$INSTALL_ROOT/tarballs"
cd "$INSTALL_ROOT/tarballs"

if [[ ! -f "$PETSC_TARBALL" ]] || ! tar -tzf "$PETSC_TARBALL" >/dev/null 2>&1; then
  echo "Download $PETSC_TARBALL ..."
  wget --tries=2 --timeout=60 --progress=dot:giga "$PETSC_URL" -O "$PETSC_TARBALL" 2>&1 | tail -5
  if ! tar -tzf "$PETSC_TARBALL" >/dev/null 2>&1; then
    echo "Primary URL failed, try alternative ftp.mcs.anl.gov ..."
    wget --tries=2 --timeout=60 --progress=dot:giga "$PETSC_URL_ALT" -O "$PETSC_TARBALL" 2>&1 | tail -5
  fi
  tar -tzf "$PETSC_TARBALL" >/dev/null 2>&1 || { echo "FEHLER: Download/extract corrupt"; rm -f "$PETSC_TARBALL"; exit 1; }
fi
sha256sum "$PETSC_TARBALL" | tee -a tarball-hashes.txt
echo "Size: $(du -h "$PETSC_TARBALL" | awk '{print $1}')"

if [[ ! -d "$PETSC_DIR_ROOT" ]]; then
  cd "$INSTALL_ROOT"
  tar -xzf "tarballs/$PETSC_TARBALL"
fi
[[ -f "$PETSC_DIR_ROOT/configure" ]] || { echo "FEHLER: PETSc extract fehlgeschlagen"; exit 1; }

grep -E "PETSC_VERSION_(MAJOR|MINOR|SUBMINOR)" "$PETSC_DIR_ROOT/include/petscversion.h" | head -3
echo "Phase 2 OK."
echo ""

###############################################
# Phase 3 - Configure
###############################################
echo "=== Phase 3: PETSc Configure ==="
cd "$PETSC_DIR_ROOT"
export PETSC_DIR="$PETSC_DIR_ROOT"
export PETSC_ARCH="$PETSC_ARCH"

# Full cleanup so PETSc re-fetches via our --download-kokkos-kernels=file://... tarball.
rm -rf "$PETSC_DIR_ROOT/$PETSC_ARCH" 2>/dev/null

# Defensive: verify local tarball Plan-I marks are present.
# β5h: tarball is kokkos-kernels-develop-plan-i.tar.gz, top-dir is kokkos-kernels/
PLANI_TGZ=/opt/openfoam-v2512/tarballs/kokkos-kernels-develop-plan-i.tar.gz
if [[ -f "$PLANI_TGZ" ]]; then
  PLANI_MARKS=$(tar xzOf "$PLANI_TGZ" kokkos-kernels/cmake/kokkoskernels_components.cmake 2>/dev/null | grep -c "Plan I disabled")
  echo "Plan I tarball marks: $PLANI_MARKS (expect 3)"
fi

cat > configure-bmg-opt.sh <<EOF
#!/bin/bash
# OMPI wrappers must use icx/icpx so -fsycl works at link time.
export OMPI_CC=icx
export OMPI_CXX=icpx
# β5h2: drop -g (sycl-post-link RAM-explosion bei großen Hypre-Bitcodes
# in oneAPI 2025.3); keep -O2, fp-model=precise, INTEL_GEN, KK-develop
./configure \\
  PETSC_ARCH=$PETSC_ARCH \\
  --with-cc=/usr/bin/mpicc \\
  --with-cxx=/usr/bin/mpicxx \\
  --with-fc=0 \\
  --with-debugging=0 \\
  --with-precision=double \\
  --with-shared-libraries=1 \\
  --with-blaslapack-dir="\$MKLROOT" \\
  --with-sycl \\
  --with-syclc=icpx \\
  --SYCLPPFLAGS='-Wno-tautological-constant-compare' \\
  --COPTFLAGS='-O2' \\
  --CXXOPTFLAGS='-O2' \\
  --SYCLOPTFLAGS='-O2' \\
  --SYCLFLAGS='-fsycl -fp-model=precise' \\
  --download-kokkos \\
  --download-kokkos-cmake-arguments='-DKokkos_ARCH_INTEL_GEN=ON' \\
  --download-kokkos-kernels=file:///opt/openfoam-v2512/tarballs/kokkos-kernels-develop-plan-i.tar.gz \\
  --download-kokkos-kernels-cmake-arguments='-DKokkos_ARCH_INTEL_GEN=ON' \\
  --download-hypre \\
  --download-hypre-commit=origin/master \\
  --download-hypre-configure-arguments='--enable-unified-memory' \\
  --download-umpire \\
  --download-caliper
EOF
chmod +x configure-bmg-opt.sh

START_TS=$(date +%s)
./configure-bmg-opt.sh 2>&1 | tee configure.log
CFG_RC=${PIPESTATUS[0]}
CFG_DURATION=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "Configure: rc=$CFG_RC, ${CFG_DURATION}min"

if (( CFG_RC != 0 )); then
  echo "FEHLER: PETSc configure rc=$CFG_RC"
  echo "--- Letzte 50 Zeilen configure.log ---"
  tail -50 configure.log
  echo "--- arch/conf/configure.log Tail ---"
  tail -50 "$PETSC_ARCH/lib/petsc/conf/configure.log" 2>/dev/null
  exit 1
fi

# Verify SYCL/Kokkos/Hypre/Umpire in petscvariables
echo "--- petscvariables key entries ---"
grep -E "^(SYCLC|HYPRE_LIB|KOKKOS_LIB|UMPIRE_LIB|CALIPER_LIB|PETSC_HAVE_SYCL|PETSC_HAVE_KOKKOS|PETSC_HAVE_HYPRE|PETSC_HAVE_UMPIRE)" \
  "$PETSC_ARCH/lib/petsc/conf/petscvariables" 2>/dev/null | head -20

echo "Phase 3 OK."
echo ""

###############################################
# Phase 4 - Build
###############################################
echo "=== Phase 4: PETSc Build ==="
cd "$PETSC_DIR_ROOT"

START_TS=$(date +%s)
make PETSC_DIR="$PETSC_DIR_ROOT" PETSC_ARCH="$PETSC_ARCH" -j 16 all 2>&1 | tee make.log
BUILD_RC=${PIPESTATUS[0]}
BUILD_DURATION=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "Build: rc=$BUILD_RC, ${BUILD_DURATION}min"

if (( BUILD_RC != 0 )); then
  echo "FEHLER: make rc=$BUILD_RC"
  echo "--- Letzte 100 Zeilen make.log ---"
  tail -100 make.log
  exit 1
fi

ls -la "$PETSC_ARCH/lib/libpetsc."* 2>&1 | head -3
echo "Phase 4 OK."
echo ""

###############################################
# Phase 5 - make check (CPU)
###############################################
echo "=== Phase 5: PETSc make check (CPU) ==="
cd "$PETSC_DIR_ROOT"
make PETSC_DIR="$PETSC_DIR_ROOT" PETSC_ARCH="$PETSC_ARCH" check 2>&1 | tee check.log
CHECK_RC=${PIPESTATUS[0]}

# Success criteria: ex19 + ex19_HYPRE must pass. ex3k aijkokkos+ILU0 may fail
# due to IGC (Intel Graphics Compiler) Internal Compiler Error on Battlemage SYCL
# JIT for KokkosSparse spiluk - irrelevant for our Hypre+BoomerAMG sanity.
EX19_OK=$(grep -c "ex19 run successfully" check.log)
EX19_HYPRE_OK=$(grep -c "ex19 run successfully with HYPRE" check.log)
EX3K_FAIL=$(grep -c "ex3k.*Kokkos Kernels" check.log || true)
echo "Phase 5 results: ex19=${EX19_OK}, ex19_HYPRE=${EX19_HYPRE_OK}, ex3k_fail=${EX3K_FAIL}"
if (( EX19_OK >= 2 )) && (( EX19_HYPRE_OK >= 1 )); then
  echo "Phase 5 OK (ex19 + Hypre passed; ex3k IGC-bug tolerated)."
else
  echo "FEHLER: critical tests failed"
  tail -40 check.log
  exit 1
fi
echo ""

###############################################
# Phase 6 - GPU Sanity
###############################################
echo "=== Phase 6: GPU-Sanity (ex2 200x200, CPU-baseline + Kokkos+SYCL+Hypre) ==="
cd "$PETSC_DIR_ROOT/src/ksp/ksp/tutorials"
# Force rebuild to ensure ex2 links against current oneAPI 2025.3 libs
# (a stale binary from earlier 2026.0 run had RPATH/symbols mismatch)
rm -f ex2 ex2.o
make ex2 2>&1 | tail -5
[[ -x ./ex2 ]] || { echo "FEHLER: ex2 binary fehlt"; exit 1; }
echo "ex2 freshly linked; ldd shows libsycl from:"
ldd ./ex2 2>&1 | grep -i sycl | head -3

GPU_MON_LOG=/tmp/stufe2-igt-monitor.json

# 6a. Background monitor: intel_gpu_top JSON 1Hz to detect compute engine activity.
# B70 is renderD129 (assumption from /dev/dri layout); fall back to default device.
GPU_DEV=/dev/dri/renderD129
[[ -e "$GPU_DEV" ]] || GPU_DEV=/dev/dri/renderD128
intel_gpu_top -d drm:$GPU_DEV -J -s 1000 > "$GPU_MON_LOG" 2>/dev/null &
MON_PID=$!
trap "kill $MON_PID 2>/dev/null || true" EXIT
sleep 2  # let monitor settle

# Pre-run VRAM (sysfs, if exposed)
echo "--- pre-run VRAM (sysfs) ---"
for f in /sys/class/drm/card*/device/mem_info_vram_used; do
  [[ -r "$f" ]] && echo "$f : $(cat $f) bytes"
done 2>&1 | head -5

# 6b. CPU-baseline run
echo "--- CPU baseline (no Kokkos) ---"
mpirun -np 1 ./ex2 -m 200 -n 200 \
  -ksp_type cg -pc_type hypre -pc_hypre_type boomeramg \
  -ksp_monitor -ksp_max_it 200 \
  -log_view 2>&1 | tee run-cpu.log | grep -E "Norm|^KSPSolve |^MatMult |^Time " | head -20
CPU_RC=${PIPESTATUS[0]}

# 6c. GPU run with l1-Jacobi (GPU-safe relax).
# -use_gpu_aware_mpi 0: System-OpenMPI is not SYCL-GPU-aware; opt out of strict check.
echo "--- GPU run (Kokkos+SYCL+Hypre+UM, l1-Jacobi relax) ---"
mpirun -np 1 ./ex2 -m 200 -n 200 \
  -mat_type aijkokkos -vec_type kokkos \
  -use_gpu_aware_mpi 0 \
  -ksp_type cg -pc_type hypre -pc_hypre_type boomeramg \
  -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi \
  -ksp_monitor -ksp_max_it 200 \
  -log_view 2>&1 | tee run-gpu.log | grep -E "Norm|^KSPSolve |^MatMult |Kokkos|SYCL|^Time " | head -30
GPU_RC=${PIPESTATUS[0]}

# 6d. stop monitor
kill $MON_PID 2>/dev/null || true
sleep 2

# Post-run VRAM
echo "--- post-run VRAM (sysfs) ---"
for f in /sys/class/drm/card*/device/mem_info_vram_used; do
  [[ -r "$f" ]] && echo "$f : $(cat $f) bytes"
done 2>&1 | head -5

# 6e. Analyze monitor: look for compute/render engine busy > 0
GPU_BUSY_PEAK=$(grep -oE '"busy"[^,}]*' "$GPU_MON_LOG" 2>/dev/null \
  | grep -oE "[0-9.]+" | sort -n | tail -1)
echo "intel_gpu_top peak engine busy: ${GPU_BUSY_PEAK:-NA}%"

# 6f. Convergence/timing extraction
CPU_ITERS=$(grep -c "KSP Residual norm" run-cpu.log)
GPU_ITERS=$(grep -c "KSP Residual norm" run-gpu.log)
CPU_TIME=$(awk '/^KSPSolve / {print $4; exit}' run-cpu.log)
GPU_TIME=$(awk '/^KSPSolve / {print $4; exit}' run-gpu.log)
echo "CPU: $CPU_ITERS iter, KSPSolve ${CPU_TIME}s"
echo "GPU: $GPU_ITERS iter, KSPSolve ${GPU_TIME}s"

# 6g. Backend confirmation (look for Kokkos/SYCL ops in log_view)
BACKEND_OK=NEIN
if grep -qE "aijkokkos|MatMult_SeqAIJKokkos|VecKokkos|SYCL" run-gpu.log; then
  BACKEND_OK=YES
fi
echo "Backend Kokkos/SYCL in log_view: $BACKEND_OK"

# Sanity gate
(( CPU_RC == 0 && GPU_RC == 0 )) || { echo "FEHLER: ex2 returned CPU=$CPU_RC GPU=$GPU_RC"; exit 1; }
[[ "$BACKEND_OK" == "YES" ]] || { echo "FEHLER: GPU log_view zeigt keine Kokkos/SYCL-Operationen"; exit 1; }

echo "Phase 6 OK."
echo ""

###############################################
# Phase 7 - Bericht
###############################################
echo "=== Phase 7: Bericht ==="
DISK_USED=$(du -sBG "$PETSC_DIR_ROOT" 2>/dev/null | awk '{print $1}')
PASS_COUNT=$(grep -c "passed" check.log 2>/dev/null)

cat <<EOF

============================================
STUFE 2 BERICHT - PETSc 3.25.1 + Hypre + Kokkos + SYCL
============================================
Datum:                      $(date -Iseconds)
Sudo-Modus:                 ${SUDO_MODE}
Apt installierte Pkgs:      ${APT_INSTALLED_COUNT} (opencl-headers, ocl-icd-opencl-dev)
GPU-Monitor:                ${GPU_MON_TOOL}

ESI v2512:                  $WM_PROJECT_DIR
oneAPI:                     ${ONEAPI_SETVARS}
MKLROOT:                    ${MKLROOT}
icpx:                       $(icpx --version 2>/dev/null | head -1)
mpicc:                      $(mpicc --version 2>/dev/null | head -1)

PETSc Source:               Tarball, ${PETSC_VER}
PETSc Configure:            rc=$CFG_RC, ${CFG_DURATION}min
PETSc Build:                rc=$BUILD_RC, ${BUILD_DURATION}min
PETSc make check:           ${PASS_COUNT} 'passed' lines

GPU-Sanity (ex2 200x200):
  CPU-Baseline:             ${CPU_ITERS} iter, KSPSolve ${CPU_TIME}s
  GPU (Kokkos+SYCL+Hypre):  ${GPU_ITERS} iter, KSPSolve ${GPU_TIME}s
  GPU engine busy (peak):   ${GPU_BUSY_PEAK:-NA}%
  Backend bestaetigt:       ${BACKEND_OK}

Disk used:                  $DISK_USED ($PETSC_DIR_ROOT)

Empfehlung Stufe 3: $( (( CFG_RC==0 && BUILD_RC==0 && GPU_RC==0 )) && [[ "$BACKEND_OK" == "YES" ]] && echo GO || echo NOGO )
============================================
EOF
