# OpenFOAM v2512 + PETSc + Kokkos + SYCL on Intel Arc Pro B70 — Pioneer Documentation

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![OpenFOAM](https://img.shields.io/badge/OpenFOAM-ESI%20v2512-green)](https://www.openfoam.com)
[![PETSc](https://img.shields.io/badge/PETSc-3.25.1-orange)](https://petsc.org)
[![Hypre](https://img.shields.io/badge/Hypre-master%20%2B%20UM-purple)](https://github.com/hypre-space/hypre)
[![Kokkos](https://img.shields.io/badge/KokkosKernels-5.1.0%20BATCHED%3DOFF-red)](https://github.com/kokkos/kokkos-kernels)
[![Intel Arc Pro B70](https://img.shields.io/badge/Intel%20Arc%20Pro-B70%20Pro%2032GB-blue)](https://www.intel.com/content/www/us/en/products/sku/245797)
[![Status](https://img.shields.io/badge/Stage-Stufe%202%20GO%20%E2%80%94%20Stufe%203%20pending-brightgreen)]()

> **TL;DR: PETSc 3.25.1 with Kokkos+SYCL+Hypre BoomerAMG works on B70 — but only after 14 patch iterations.**
>
> oneAPI 2025.3.3 (NOT 2026 — DPCT deprecated) ✅
> KokkosKernels 5.1.0 with BATCHED component disabled (CMake force-set patched out) ✅
> PETSc `aijkok.kokkos.cxx` patched (one VPB-Jacobi function stubbed) ✅
> Hypre develop-branch (release breaks on DPL/DPCT mismatch) ✅
> ex2 200×200 sanity: aijkokkos + Hypre BoomerAMG + l1scaled-jacobi converges, backend confirmed ✅
> System-OpenMPI not GPU-aware → `-use_gpu_aware_mpi 0` mandatory at runtime

This repo documents the build path for OpenFOAM v2512 (ESI) coupled to
PETSc 3.25.1 with GPU offloading via Kokkos+SYCL on Intel Arc Pro B70 Pro
(Battlemage Xe2-HPG). It is the second iteration after our [pure-Ginkgo
attempt with Foundation OpenFOAM 13](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)
which concluded that no working SYCL preconditioner shipped in Ginkgo 1.10/1.11.
PETSc 3.25 + Hypre BoomerAMG via Kokkos-SYCL is the alternative path.

**Status (Stufe 2):** Build pipeline GREEN. All upstream incompatibilities
either patched, worked-around, or filed for upstream. Stufe 3 (petsc4Foam
adapter integration with the 34M-cell automotive testcase) is the next
milestone.

---

## What "Plan I" Means

We hit 14 distinct upstream incompatibilities while bringing this stack up
on a fresh Ubuntu 26.04 + B70 system. Plan I is the convergent set of
patches and workarounds that produce a working build. Each one is
documented in a separate [`finding`](findings/) with diagnosis, fix and
upstream status.

| # | Finding | Layer | Type |
|---|---|---|---|
| [01](findings/01_libparmetis_replaced_libscotchparmetis_u26.md) | `libparmetis-dev` removed in U26.04 | apt | swap |
| [02](findings/02_scotch_6_1_0_gcc15_strict_prototype.md) | scotch 6.1.0 K&R protos vs GCC 15 | ESI ThirdParty | switch to system-scotch |
| [03](findings/03_esi_repo_login_required_tarball_fallback.md) | ESI git-repo privatized | source-fetch | tarball mirror |
| [04](findings/04_set_u_bashrc_184_unbound.md) | `set -u` exits on OF bashrc:184 | shell | drop `-u` global |
| [05](findings/05_oneapi_intel_mpi_path_priority.md) | oneAPI prepends Intel-MPI; ESI built sys-openmpi | PATH | force `/usr/bin` first + `OMPI_CC=icx` |
| [06](findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md) | `/usr/bin/ocloc 24.35` doesn't know Battlemage | SYCL AOT | drop `-fsycl-targets`, JIT only |
| [07](findings/07_kk_batched_sycl_strict_spec.md) | KokkosKernels `BatchedDblBufGemm` reference-member kernel param | KokkosKernels SYCL | source-level architectural |
| [08](findings/08_kk_components_force_batched_via_sparse.md) | SPARSE FORCE-enables BATCHED in cmake | KokkosKernels CMake | patch `kokkoskernels_components.cmake` |
| [09](findings/09_petsc_local_tarball_file_url.md) | PETSc ignores local tarball without `file://` | PETSc configure | URL scheme prefix |
| [10](findings/10_oneapi_2026_dpct_2025_3_mismatch.md) | DPCT deprecated in 2026; DPL still references it | oneAPI version | install 2025.3.3 in parallel |
| [11](findings/11_hypre_master_required.md) | Hypre release tries `dpct::constant_iterator`; develop has fix | Hypre | `--download-hypre-commit=origin/master` |
| [12](findings/12_aijkok_kokkosbatched_dependency.md) | PETSc aijkok needs `KokkosBatched_*Decl.hpp` | PETSc source | comment includes + SETERRQ stub |
| [13](findings/13_use_gpu_aware_mpi_off.md) | System-OpenMPI not SYCL-GPU-aware | runtime | `-use_gpu_aware_mpi 0` |
| [14](findings/14_ex3k_igc_compiler_error_battlemage.md) | IGC ICE on KokkosSparse spiluk JIT for B70 | backend | tolerated, not in our path |

---

## Hardware

| Component | Spec |
|---|---|
| GPU | Intel Arc Pro B70 Pro (Battlemage BMG-G31) — 32 GB GDDR6 ECC |
| CPU | Intel Core Ultra 9 285K (8P+16E, 24 threads) |
| RAM | 96 GB DDR5-6800 |
| OS | Ubuntu 26.04 LTS (resolute), Kernel 7.0.0-15 |
| GPU Driver | xe + Intel Compute Runtime 26.05.37020.3 (CR-pinned) |

See [hardware.md](hardware.md) for full performance characterization (FP64,
VRAM bandwidth, kernel-launch). Hardware spec is identical to our
[earlier B70 Pro repo](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro).

---

## Software Stack (Verified Working)

| Component | Version | Notes |
|---|---|---|
| ESI OpenFOAM | v2512 | Tarball from `dl.openfoam.com`; built with system-scotch (see [findings/02](findings/02_scotch_6_1_0_gcc15_strict_prototype.md)) |
| Foundation OpenFOAM 13 | 13 | Coexists in `/opt/openfoam13/` — untouched by this build |
| Intel oneAPI Base Toolkit | **2025.3.3** (file: `intel-oneapi-base-toolkit-2025.3.2.21_offline.sh`) | Installed parallel to 2026 in `/opt/intel/oneapi/2025.3/`; 2026 unusable due to DPCT deprecation ([findings/10](findings/10_oneapi_2026_dpct_2025_3_mismatch.md)) |
| icpx | 2025.3.3 (build 20260319) | SYCL host+device compiler |
| MPI | System-OpenMPI (Ubuntu) with `OMPI_CC=icx OMPI_CXX=icpx` | Same MPI as ESI v2512; not GPU-aware ([findings/13](findings/13_use_gpu_aware_mpi_off.md)) |
| PETSc | 3.25.1 + [Plan I patches](patches/plan-i.patch) | `--download-kokkos --download-kokkos-kernels=file://...patched.tar.gz --download-hypre --download-hypre-commit=origin/master --download-umpire --download-caliper --download-hypre-configure-arguments='--enable-unified-memory'` |
| KokkosKernels | 5.1.0 + components.cmake patch | BATCHED component disabled to bypass [findings/07](findings/07_kk_batched_sycl_strict_spec.md) |
| Kokkos | bundled (PETSc default) | SYCL backend |
| Hypre | develop branch (origin/master) | BoomerAMG with `--enable-unified-memory` |
| Umpire / Caliper | bundled | memory pool / instrumentation |

See [setup/install_stack.md](setup/install_stack.md) for the full
reproduction recipe.

---

## Verification

```bash
mpirun -np 1 ./ex2 -m 200 -n 200 \
  -mat_type aijkokkos -vec_type kokkos \
  -use_gpu_aware_mpi 0 \
  -ksp_type cg -pc_type hypre -pc_hypre_type boomeramg \
  -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi \
  -ksp_monitor -ksp_max_it 200 -log_view
```

| Run | Iter | KSPSolve | Norm of error |
|---|---|---|---|
| CPU baseline (no `-mat_type aijkokkos`) | 5 | 1.16e-02 s | 4.56e-05 |
| GPU (Kokkos+SYCL+Hypre+UM) | 10 | 1.97e-01 s | 6.40e-05 |

`log_view` confirms `MatMult_SeqAIJKokkos`, `VecKokkos`, `SYCL`-tagged ops.
`ldd ex2` confirms `libsycl.so.8` from `/opt/intel/oneapi/2025.3/compiler/2025.3/lib/`.

GPU is **17× slower** than CPU at this 40k-unknown problem — expected: SYCL
JIT-compile + host-device transfer dominate at small scale. The Stufe 3
testcase (34M cells) should reverse this.

See [benchmarks/ex2_200x200_results.md](benchmarks/ex2_200x200_results.md)
for full run details.

---

## Repository Structure

```
├── README.md            — This file
├── NOTICE.md            — 3rd-party license attribution (PETSc, Kokkos, Hypre, etc.)
├── hardware.md          — Full hardware specs and measured performance
├── conclusions.md       — Honest verdict: Stufe 2 GO, what's blocked, what's next
├── references.md        — Cross-refs to upstream papers, projects, sister repo
├── setup/
│   ├── install_stack.md — Stufe 1 (ESI v2512) + Stufe 2 (PETSc + GPU stack)
│   └── bios_settings.md — BIOS optimization for compute workloads (same hardware)
├── scripts/
│   ├── stufe1-esi-v2512-tarball.sh — Stufe 1 build (idempotent)
│   ├── stufe2-petsc.sh             — Stufe 2 build with Plan I integrated
│   └── README.md
├── configs/
│   ├── petsc-configure-bmg-opt.sh  — extracted PETSc configure invocation
│   └── README.md
├── patches/
│   ├── plan-i.patch                — Source-level patches (PETSc + KokkosKernels CMake)
│   └── README.md
├── findings/            — 14 root-cause findings (Plan I)
├── logs/
│   ├── stufe1-master.log           — Stufe 1 build output (trimmed)
│   ├── stufe2-master.log           — Stufe 2 successful run
│   ├── plan-i-iterations.md        — Chronological iteration log
│   └── README.md
├── benchmarks/
│   ├── ex2_200x200_results.md      — Phase-6 sanity numbers
│   └── README.md
├── .github/
│   ├── ISSUE_TEMPLATE/             — Bug, question, config
│   └── PULL_REQUEST_TEMPLATE.md
├── LICENSE                         — GPL-3.0-or-later (own work)
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
└── SECURITY.md
```

---

## License

This repository's **own work** (READMEs, findings, build scripts, patch
documentation) is licensed under **GPL-3.0-or-later** — see [LICENSE](LICENSE).

This repository **does not redistribute** any third-party source code. It
documents and patches code from upstream projects with their own licenses,
which the user fetches and builds locally. See [NOTICE.md](NOTICE.md) for
the full third-party license map (PETSc BSD-2, Kokkos/KokkosKernels BSD-3,
Hypre Apache-2.0/MIT, Umpire/Caliper BSD-3, ESI OpenFOAM GPL-3, Scotch
CeCILL-C, Intel oneAPI EULA — none redistributed).

---

## How to Cite

```bibtex
@misc{gleu2026petscb70,
  author = {Gleu, Heiko},
  title  = {OpenFOAM v2512 + PETSc + Kokkos + SYCL on Intel Arc Pro B70:
             Pioneer Documentation of Plan I (14 patches to a working
             GPU-offloading build)},
  year   = {2026},
  url    = {https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70}
}
```

---

## Related Projects

- [hpsim/petsc4Foam](https://gitlab.com/hpsim/petsc4Foam) — PETSc adapter for OpenFOAM (Stufe 3 target)
- [petsc/petsc](https://gitlab.com/petsc/petsc) — PETSc upstream (BSD-2)
- [hypre-space/hypre](https://github.com/hypre-space/hypre) — Hypre upstream (Apache-2.0)
- [kokkos/kokkos-kernels](https://github.com/kokkos/kokkos-kernels) — KokkosKernels upstream
- [PMZFX/intel-arc-pro-b70-benchmarks](https://github.com/PMZFX/intel-arc-pro-b70-benchmarks) — B70 LLM/video benchmarks (oneAPI 2025.3+ requirement source)
- [heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro) — sister repo: pure-Ginkgo attempt with Foundation OF13
- [Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes](https://github.com/Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes) — Ubuntu/B70 driver workarounds (parallel pioneer work)

---

## Status (May 2026)

- **Stufe 1 (ESI OpenFOAM v2512):** GO — `icoFoam` cavity serial + parallel-4 converges
- **Stufe 2 (PETSc + Kokkos + SYCL + Hypre):** GO — ex2 GPU sanity passes, backend confirmed
- **Stufe 3 (petsc4Foam adapter + 34M-cell automotive case):** PENDING

When you reproduce, expect **45–90 min** of build time on a 24-core
machine after Plan I is in place. From scratch (downloads + retries) the
13-iteration discovery process took ≈ 4 hours. This repo cuts that to
≈ 1 hour by handing you Plan I directly.

*Pioneer documentation independently maintained.*
*Full reproducibility intended for the next Battlemage CFD pioneer.*
