#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Heiko Gleu
# Plan I build script — see https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70
# This script invokes (does not redistribute) third-party software. See NOTICE.md.

# Stufe 1 Tarball-Pfad: ESI OpenFOAM v2512 build via dl.openfoam.com tarballs.
# git-clone war blockiert (develop.openfoam.com hat openfoam.git privatisiert).

set -o pipefail
# Note: -u (nounset) was removed because OpenFOAM's etc/bashrc references
# unbound vars (line 184); in non-interactive shells -u causes immediate exit.
# Defensive checks below use ${var:-} syntax explicitly.

unset WM_PROJECT_DIR FOAM_INST_DIR WM_PROJECT WM_PROJECT_VERSION WM_PROJECT_INST_DIR
unset WM_THIRD_PARTY_DIR WM_OPTIONS WM_COMPILER WM_COMPILE_OPTION
unset FOAM_APP FOAM_APPBIN FOAM_LIBBIN FOAM_TUTORIALS FOAM_RUN FOAM_USER_APPBIN FOAM_USER_LIBBIN

INSTALL_ROOT=/opt/openfoam-v2512
SUDO_MODE="pkexec-prep (vorab)"
PKGS_INSTALLED=9
SOURCE_METHOD="tarball (dl.openfoam.com)"

###############################################
# Phase 3' - Tarball download + extract
###############################################
echo "=== Phase 3' : Tarball Download + Extract ==="
cd "$INSTALL_ROOT"

DL_BASE=https://dl.openfoam.com/source/v2512
TARBALLS=( OpenFOAM-v2512.tgz ThirdParty-v2512.tar.gz )

START_TS=$(date +%s)
for tb in "${TARBALLS[@]}"; do
  if [[ ! -f "$tb" ]]; then
    echo "--- Download $tb ---"
    wget --tries=3 --timeout=60 --progress=dot:giga "$DL_BASE/$tb" 2>&1 | tail -5
    if [[ ! -f "$tb" ]]; then
      echo "FEHLER: $tb nicht heruntergeladen"
      exit 1
    fi
  else
    echo "$tb existiert bereits, skip download."
  fi
  echo "Size: $(du -h "$tb" | awk '{print $1}')"
done
DL_DUR=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "Download: ${DL_DUR}min"

echo "--- Extract ---"
START_TS=$(date +%s)
for tb in "${TARBALLS[@]}"; do
  echo "Extracting $tb ..."
  tar -xzf "$tb"
done
EX_DUR=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "Extract: ${EX_DUR}min"

# Verify expected directories
[[ -d OpenFOAM-v2512 ]] || { echo "FEHLER: OpenFOAM-v2512/ fehlt nach Extract"; ls -la; exit 1; }
[[ -d ThirdParty-v2512 ]] || { echo "FEHLER: ThirdParty-v2512/ fehlt nach Extract"; ls -la; exit 1; }
[[ -f OpenFOAM-v2512/etc/bashrc ]] || { echo "FEHLER: etc/bashrc fehlt"; exit 1; }
echo "Tarball-Quelle OK."
echo ""

###############################################
# Phase 4 - ENV setzen und ThirdParty bauen
###############################################
echo "=== Phase 4: ENV + ThirdParty-Build ==="

export FOAM_INST_DIR=$INSTALL_ROOT
# shellcheck disable=SC1090,SC1091
source "$INSTALL_ROOT/OpenFOAM-v2512/etc/bashrc" \
  WM_COMPILER=Gcc WM_LABEL_SIZE=32 WM_PRECISION_OPTION=DP \
  WM_COMPILE_OPTION=Opt FOAMY_HEX_MESH=yes

if [[ "${WM_PROJECT_DIR:-}" != "$INSTALL_ROOT/OpenFOAM-v2512" ]]; then
  echo "FEHLER: WM_PROJECT_DIR falsch: ${WM_PROJECT_DIR:-<unset>}"
  exit 1
fi
echo "WM_PROJECT_DIR: $WM_PROJECT_DIR"
echo "WM_THIRD_PARTY_DIR: $WM_THIRD_PARTY_DIR"

cd "$WM_THIRD_PARTY_DIR"
START_TS=$(date +%s)
./Allwmake -j 16 -s -q 2>&1 | tee log.allwmake.thirdparty
TP_RC=${PIPESTATUS[0]}
TP_DURATION=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "ThirdParty Build: rc=$TP_RC, ${TP_DURATION}min"
if grep -E "FATAL|Error 2" log.allwmake.thirdparty | grep -v ADIOS2 | head -3; then
  echo "FEHLER: FATAL in ThirdParty-Build (nicht ADIOS2-related)"
  exit 1
fi
echo ""

###############################################
# Phase 5 - OpenFOAM Core bauen
###############################################
echo "=== Phase 5: Core-Build ==="
cd "$WM_PROJECT_DIR"
START_TS=$(date +%s)
./Allwmake -j 16 -s -q 2>&1 | tee log.allwmake.core
CORE_RC=${PIPESTATUS[0]}
CORE_DURATION=$(( ( $(date +%s) - START_TS ) / 60 ))
echo "Core Build: rc=$CORE_RC, ${CORE_DURATION}min"

ERRCOUNT=$(grep -cE "Error|FATAL" log.allwmake.core || true)
echo "Error/FATAL-Lines im Log: $ERRCOUNT"

if (( CORE_RC != 0 )); then
  echo "FEHLER: Core-Build returned $CORE_RC"
  echo "Letzte 30 Zeilen log.allwmake.core:"
  tail -30 log.allwmake.core
  exit 1
fi
echo ""

###############################################
# Phase 6 - foamInstallationTest
###############################################
echo "=== Phase 6: foamInstallationTest ==="
foamInstallationTest 2>&1 | tee log.installtest.txt | tail -30
if grep -q "Critical systems ok" log.installtest.txt; then
  echo "foamInstallationTest OK."
else
  echo "FEHLER: 'Critical systems ok' nicht gefunden"
  exit 1
fi
echo ""

###############################################
# Phase 7 - icoFoam Cavity (serial + parallel)
###############################################
echo "=== Phase 7: icoFoam Cavity Sanity ==="
TESTCASE_ROOT=/home/heiko/CFD-Cases/Testcase-petsc4Foam-ESI
mkdir -p "$TESTCASE_ROOT"

rm -rf "$TESTCASE_ROOT/cavity-serial"
cp -r "$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity" "$TESTCASE_ROOT/cavity-serial"
cd "$TESTCASE_ROOT/cavity-serial"
blockMesh > log.blockMesh 2>&1 || { echo "FEHLER: blockMesh"; exit 1; }
icoFoam > log.icoFoam.serial 2>&1
if ! tail -1 log.icoFoam.serial | grep -q "End"; then
  echo "FEHLER: icoFoam serial kein 'End'"
  tail -20 log.icoFoam.serial
  exit 1
fi
echo "icoFoam serial OK."

rm -rf "$TESTCASE_ROOT/cavity-parallel"
cp -r "$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity" "$TESTCASE_ROOT/cavity-parallel"
cd "$TESTCASE_ROOT/cavity-parallel"
cat > system/decomposeParDict <<'EOF'
FoamFile { version 2.0; format ascii; class dictionary; object decomposeParDict; }
numberOfSubdomains 4;
method scotch;
EOF
blockMesh > log.blockMesh 2>&1
decomposePar > log.decomposePar 2>&1 || { echo "FEHLER: decomposePar"; exit 1; }
mpirun -np 4 icoFoam -parallel > log.icoFoam.parallel 2>&1
if ! tail -5 log.icoFoam.parallel | grep -q "End"; then
  echo "FEHLER: icoFoam parallel kein 'End'"
  tail -20 log.icoFoam.parallel
  exit 1
fi
reconstructPar > log.reconstructPar 2>&1
echo "icoFoam parallel 4 Ranks OK."
echo ""

###############################################
# Phase 8 - Bericht
###############################################
echo "=== Phase 8: Bericht ==="
DISK_USED=$(du -sBG "$INSTALL_ROOT" 2>/dev/null | awk '{print $1}')

cat <<EOF

============================================
STUFE 1 BERICHT - ESI OpenFOAM v2512 Build
============================================
Datum:                  $(date -Iseconds)
OS:                     $(lsb_release -ds)
Kernel:                 $(uname -r)
oneAPI Pfad:            $(ls -d /opt/intel/oneapi/2026.* 2>/dev/null | head -1)
Sudo-Modus:             ${SUDO_MODE}
Apt installierte Pkgs:  ${PKGS_INSTALLED} (libparmetis-dev->libscotchparmetis-dev unter U26.04)
Source-Methode:         ${SOURCE_METHOD}

WM_PROJECT_DIR:         $WM_PROJECT_DIR
ThirdParty Build:       rc=$TP_RC,   ${TP_DURATION}min
Core Build:             rc=$CORE_RC, ${CORE_DURATION}min
Error/FATAL im Log:     $ERRCOUNT (ohne ADIOS2-Warnungen)
foamInstallationTest:   OK
icoFoam serial:         OK
icoFoam parallel 4:     OK

Disk used $INSTALL_ROOT: $DISK_USED

Empfehlung Stufe 2: GO
============================================
EOF
