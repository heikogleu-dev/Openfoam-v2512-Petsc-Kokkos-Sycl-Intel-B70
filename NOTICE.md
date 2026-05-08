# NOTICE — Third-Party Software Attribution

This repository (own work — READMEs, findings, build scripts, patch
documentation) is licensed under **GPL-3.0-or-later** (see [LICENSE](LICENSE)).

It **does not redistribute** any third-party source code or binaries. It
documents how to fetch and build upstream software locally, and provides
patch documentation describing modifications you may apply to *your* local
copies. The third-party projects retain their own licenses, summarised below.

---

## Build-time Dependencies (User Fetches & Installs Locally)

| Project | License | Source URL |
|---|---|---|
| **PETSc 3.25.1** | BSD-2-Clause | https://petsc.org / https://gitlab.com/petsc/petsc |
| **Kokkos** | BSD-3-Clause | https://github.com/kokkos/kokkos |
| **KokkosKernels 5.1.0** | BSD-3-Clause | https://github.com/kokkos/kokkos-kernels |
| **Hypre** (develop branch) | Apache-2.0 + MIT (dual) | https://github.com/hypre-space/hypre |
| **Umpire** (LLNL) | BSD-3-Clause (LLNL-CODE) | https://github.com/LLNL/Umpire |
| **Caliper** (LLNL) | BSD-3-Clause (LLNL-CODE) | https://github.com/LLNL/Caliper |
| **ESI OpenFOAM v2512** (OpenCFD Ltd.) | GPL-3.0-or-later | https://www.openfoam.com / https://dl.openfoam.com/source/v2512/ |
| **Scotch / PT-Scotch 7.x** | CeCILL-C (LGPL-compatible) | https://gitlab.inria.fr/scotch/scotch (used via Ubuntu `libscotch-dev` apt-package) |
| **Intel oneAPI Base Toolkit 2025.3** | Intel Simplified Software License (binary EULA) | https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit-download.html |
| **Intel Compute Runtime / Level-Zero** | MIT (NEO + libze) | https://github.com/intel/compute-runtime / https://github.com/oneapi-src/level-zero |

---

## Patch Documentation (`patches/plan-i.patch`)

Plan-I describes modifications to:
- **PETSc 3.25.1** source file `src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx` —
  derivative work governed by PETSc's BSD-2-Clause license. The patch is
  documented here as instructions to be applied locally, not redistributed
  source.
- **KokkosKernels 5.1.0** CMake file `cmake/kokkoskernels_components.cmake` —
  derivative work governed by KokkosKernels' BSD-3-Clause license. Same
  treatment.

When you apply these patches to your local PETSc / KokkosKernels copies,
those modified files remain under their original BSD licenses (BSD allows
modification with attribution preserved). The *prose describing the patches*
in this repository is GPL-3.0 (own work).

---

## Reference Material (Linked, Not Redistributed)

This repository links to (does not vendor) datasheets, papers, and
documentation from:
- Intel Corporation (oneAPI release notes, B70 product pages)
- Argonne National Laboratory (PETSc website, Aurora HPC docs)
- KIT (Karlsruhe Institute of Technology — OGL/Ginkgo papers)
- Phoronix (B70 reviews)
- LLNL (Hypre, Umpire, Caliper documentation)

These are referenced under fair-use / academic-citation conventions; no
content is reproduced beyond what is necessary to identify the source.

---

## Trademarks

- **Intel®**, **Arc™**, **Battlemage™**, **oneAPI**, **icpx**, **MKL**,
  **Level Zero** are trademarks of Intel Corporation.
- **OpenFOAM®** is a registered trademark of OpenCFD Ltd. (ESI Group).
  Foundation OpenFOAM is maintained separately by The OpenFOAM Foundation
  (the v13 line in the sister repo).
- **Kokkos** and **Trilinos** are projects of the U.S. Department of Energy
  / Sandia National Laboratories.
- **Hypre**, **Umpire**, **Caliper** are projects of LLNL.
- **CUDA** is a trademark of NVIDIA Corporation (referenced for comparison only;
  no CUDA code in this repo).

These names are used here for **identification purposes only**; no
endorsement is implied, and the trademarks belong to their respective owners.

---

## Logs in `logs/` and Excerpts in `findings/`

Logs and error excerpts reproduced verbatim in this repository (e.g. compiler
errors from icpx, PETSc configure-log fragments, Hypre make output) are
reproduced under fair-use as **diagnostic citations** for the purpose of
documenting bugs and incompatibilities. They are bug reports, not
redistribution of upstream source.

If any project's authors wish a specific excerpt removed, please open
[an issue](https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70/issues)
or contact the maintainer; we will happily redact.

---

## What This Repository **Does Not** Contain

To be explicit about what is **not** redistributed here:

- ❌ No copy of PETSc, Kokkos, KokkosKernels, Hypre, Umpire, Caliper source
- ❌ No copy of ESI OpenFOAM v2512 source
- ❌ No copy of Intel oneAPI installers or libraries
- ❌ No copy of Intel Compute Runtime binaries
- ❌ No prebuilt `libpetsc.so`, `libsycl.so`, etc.

The user fetches all upstream source/binary directly from the canonical
upstream URLs (documented in [setup/install_stack.md](setup/install_stack.md)),
applies the locally-described Plan I patches, and builds.

---

## Questions or Concerns

If you believe this repository violates a license or trademark, please:
1. Open [an issue](https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70/issues), or
2. Contact the maintainer per [SECURITY.md](SECURITY.md).

We treat license compliance as a hard requirement and will respond
promptly to any concrete concern.
