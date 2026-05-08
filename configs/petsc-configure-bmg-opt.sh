#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Heiko Gleu
# Plan I PETSc configure reference — see https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70

# Plan I PETSc configure invocation — extracted reference for documentation.
# This is the exact configure-bmg-opt.sh that the build pipeline produces.
#
# Prerequisites (set by stufe2-petsc.sh before invoking this):
#   - $MKLROOT       = /opt/intel/oneapi/2025.3/mkl/2025.3
#   - PATH has /usr/bin first (sys-OpenMPI mpicc, NOT Intel-MPI)
#   - $OMPI_CC=icx, $OMPI_CXX=icpx
#   - cwd is the unpacked PETSc 3.25.1 source root
#   - aijkok.kokkos.cxx already patched (see ../patches/plan-i.patch)
#   - /opt/openfoam-v2512/tarballs/kokkos-kernels-5.1.0-plan-i.tar.gz exists
#
# Reference:
#   - findings/05_oneapi_intel_mpi_path_priority.md
#   - findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md
#   - findings/08_kk_components_force_batched_via_sparse.md
#   - findings/09_petsc_local_tarball_file_url.md
#   - findings/11_hypre_master_required.md
#
# License: GPL-3.0-or-later (own work). Invokes (does not redistribute) PETSc.

export OMPI_CC=icx
export OMPI_CXX=icpx

./configure \
  PETSC_ARCH=arch-bmg-opt \
  --with-cc=/usr/bin/mpicc \
  --with-cxx=/usr/bin/mpicxx \
  --with-fc=0 \
  --with-debugging=0 \
  --COPTFLAGS='-O3 -march=native' \
  --CXXOPTFLAGS='-O3 -march=native' \
  --SYCLFLAGS='-fsycl' \
  --with-sycl \
  --with-syclc=icpx \
  --with-precision=double \
  --with-blaslapack-dir="$MKLROOT" \
  --with-shared-libraries=1 \
  --download-kokkos \
  --download-kokkos-kernels=file:///opt/openfoam-v2512/tarballs/kokkos-kernels-5.1.0-plan-i.tar.gz \
  --download-hypre \
  --download-hypre-commit=origin/master \
  --download-hypre-configure-arguments='--enable-unified-memory' \
  --download-umpire \
  --download-caliper
