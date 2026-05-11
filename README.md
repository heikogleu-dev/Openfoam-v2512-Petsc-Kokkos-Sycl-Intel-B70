# OpenFOAM v2512 + PETSc + Kokkos + SYCL on Intel Arc Pro B70 — Pioneer Documentation

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![OpenFOAM](https://img.shields.io/badge/OpenFOAM-ESI%20v2512-green)](https://www.openfoam.com)
[![PETSc](https://img.shields.io/badge/PETSc-3.25.1-orange)](https://petsc.org)
[![Hypre](https://img.shields.io/badge/Hypre-master%20%2B%20UM-purple)](https://github.com/hypre-space/hypre)
[![Kokkos](https://img.shields.io/badge/KokkosKernels-5.1.0%20BATCHED%3DOFF-red)](https://github.com/kokkos/kokkos-kernels)
[![Intel Arc Pro B70](https://img.shields.io/badge/Intel%20Arc%20Pro-B70%20Pro%2032GB-blue)](https://www.intel.com/content/www/us/en/products/sku/245797)
[![Status](https://img.shields.io/badge/Stage-Build%20GO%20%E2%80%94%20AMG%20path%20blocked%20upstream-yellow)]()

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

---

## Part of the Battlemage CFD Pioneer Series

This is one of three repositories documenting CFD on Intel Arc Pro B70 (BMG-G31):

1. **[FluidX3D-Intel-B70](https://github.com/heikogleu-dev/FluidX3D-Intel-B70)** — LBM via OpenCL. **99.5 % peak bandwidth, 5 464 MLUPS** (production-ready as iteration sandbox for vehicle aero).
2. **[Openfoam13---GPU-Offloading-Intel-B70-Pro](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)** — FVM pressure solver via Ginkgo SYCL. **Hardware ready, software stack maturing** (FP64 96 %, kernel-launch CUDA-par, GPU 66 % idle waiting for plumbing).
3. **This repo — [Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70](https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70)** — PETSc-Kokkos-SYCL attempt. **Abandoned at GAMG path** — documents what doesn't work yet on this stack.

Together: first publicly documented end-to-end CFD evaluation on Battlemage Xe2 (Intel Arc Pro B70).

**Status (May 2026, β5h2):** Build pipeline GREEN. Foundation pressure
path (CG + Jacobi + `aijkokkos`) and chebyshev+jacobi (Eta, finding 21)
both run end-to-end on GPU on Release build. The GAMG-on-`aijkokkos`
path crashes with `SEGV signal 11` in shared low-level code that no
configuration-level workaround bypasses (finding 19); a debug rebuild
heals the crash but routes SPGEMM to CPU and is too slow for the 34M
automotive case (finding 20). See finding 22 for the pioneer-status
roadmap.

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

## Findings Index

| # | Title | File |
|---|---|---|
| 01 | libparmetis-dev removed in Ubuntu 26.04 — replace with libscotchparmetis-dev | [↗](findings/01_libparmetis_replaced_libscotchparmetis_u26.md) |
| 02 | Bundled Scotch 6.1.0 fails to compile under GCC 15 — switch to system Scotch | [↗](findings/02_scotch_6_1_0_gcc15_strict_prototype.md) |
| 03 | ESI GitLab now requires sign-in — fall back to public dl.openfoam.com tarballs | [↗](findings/03_esi_repo_login_required_tarball_fallback.md) |
| 04 | OpenFOAM `etc/bashrc` aborts under `set -u` — unbound `WM_PROJECT_DIR` | [↗](findings/04_set_u_bashrc_184_unbound.md) |
| 05 | oneAPI `setvars.sh` puts Intel-MPI ahead of system OpenMPI — repair PATH | [↗](findings/05_oneapi_intel_mpi_path_priority.md) |
| 06 | Legacy `/usr/bin/ocloc` cannot AOT-compile for Battlemage — drop AOT, use JIT | [↗](findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md) |
| 07 | KokkosKernels Batched GEMM violates SYCL strict-spec — kernel param not trivially copyable | [↗](findings/07_kk_batched_sycl_strict_spec.md) |
| 08 | KokkosKernels SPARSE forces BATCHED back ON — patch components.cmake | [↗](findings/08_kk_components_force_batched_via_sparse.md) |
| 09 | PETSc `--download-kokkos-kernels=...tar.gz` only honors `file://` URLs | [↗](findings/09_petsc_local_tarball_file_url.md) |
| 10 | oneAPI 2026.0 ships no DPCT — DPL still imports it; install 2025.3 in parallel | [↗](findings/10_oneapi_2026_dpct_2025_3_mismatch.md) |
| 11 | Hypre release fails on oneAPI 2025.3 DPL constructor — pull `origin/master` | [↗](findings/11_hypre_master_required.md) |
| 12 | PETSc `aijkok.kokkos.cxx` hard-depends on KokkosBatched — patch one function | [↗](findings/12_aijkok_kokkosbatched_dependency.md) |
| 13 | System OpenMPI is not SYCL-GPU-aware — set `-use_gpu_aware_mpi 0` | [↗](findings/13_use_gpu_aware_mpi_off.md) |
| 14 | `make check` ex3k triggers IGC ICE on Battlemage — backend bug, ignore for ILU | [↗](findings/14_ex3k_igc_compiler_error_battlemage.md) |
| 15 | Hypre `--enable-unified-memory` builds allocate-on-USM but compute on CPU | [↗](findings/15_hypre_um_not_real_gpu_pc.md) |
| 16 | petsc4Foam's `-eqn_*_vec_type` is ignored by PETSc | [↗](findings/16_petsc4foam_vec_type_prefix_ignored.md) |
| 17 | `aijkokkos` matrix with Hypre PC does NOT run on GPU | [↗](findings/17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) |
| 18 | Stufe-3: 34M-cell × np=8 → 90 GB DRAM explosion at Hypre BoomerAMG setup | [↗](findings/18_stufe3_34m_oom_8rank_hypre_hierarchy.md) |
| 19 | β5h2 build successful — AMG wall confirmed across all five GAMG configurations | [↗](findings/19_beta5h2_build_success_amg_wall_confirmed.md) |
| 20 | Debug build heals the GAMG crash — but setup is CPU-only and too slow for production | [↗](findings/20_debug_build_heals_crash_but_too_slow.md) |
| 21 | Eta configuration: chebyshev + jacobi — a non-AMG GPU preconditioner path on Release | [↗](findings/21_eta_chebyshev_jacobi_non_amg_gpu_path.md) |
| 22 | Pioneer status: aijkokkos + GAMG + SYCL is not productive on BMG-G31 in May 2026 | [↗](findings/22_pioneer_status_aijkokkos_gamg_sycl_not_productive.md) |
| 23 | B70 hardware is functional — the AMG wall is a software bug | [↗](findings/23_b70_hardware_functional_amg_wall_is_software.md) |
| 24 | PETSc aijkokkos SpMV reaches 79 % of Triad-peak on B70 | [↗](findings/24_petsc_aijkokkos_spmv_79_percent_triad.md) |
| 25 | Ginkgo SpMV is 3.2× faster than PETSc aijkokkos on B70 (microbenchmark) | [↗](findings/25_ginkgo_3x_faster_microbench.md) |
| 26 | oneAPI 2025.3 and 2026.0 coexist on the same workstation | [↗](findings/26_oneapi_2025_2026_coexistence.md) |

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

| Path | Build | Status | Performance vs. CPU baseline |
|---|---|---|---|
| Foundation (CG + Jacobi + `aijkokkos` + `vec_type kokkos`) | β5h2 Release | ✓ productive | unknown for MR2 (jacobi too weak for 34M without stronger PC) |
| GAMG family (5 configurations tested) | β5h2 Release | ✗ SEGV in `MatProductSymbolic_SeqAIJKokkos` (finding 19) | — |
| GAMG agg | F1 Debug | ✓ runs but setup is CPU-only, ~3× slower than Release (finding 20) | not productive at 34M |
| **chebyshev + jacobi (Eta)** | **β5h2 Release** | ✓ runs end-to-end on GPU, 0 H2D/D2H in inner loop (finding 21) | estimated 4–7× slower than CPU baseline on MR2 |
| Hypre BoomerAMG | β5h2 Release | ✓ builds and runs, but CPU-only via `MatConvert` (finding 17) | hybrid: AMG CPU + KSP loop GPU |

**β5h2 build pipeline:** Configure 8 min, total wall-clock ≈ 52 min on a 24-core machine.
Stack: PETSc 3.25.1 + Kokkos 5.1.0 + KokkosKernels develop (commit `6620b0a`) +
Hypre master + oneAPI 2025.3.3 + `Kokkos_ARCH_INTEL_GEN=ON`.

**Roadmap re-opened.** `aijkokkos` + GAMG + SYCL is not productive on BMG-G31
in May 2026 (six months after Battlemage launch). Re-evaluate when:

- Kokkos 5.2/6.0 ships with BMG-specific arch flag
- KokkosKernels SPGEMM gains BMG validation
- PETSc CI gains real Intel-GPU coverage for GAMG + `aijkokkos`

**ETA: 6–18 months.** See finding 22 for the full pioneer-status analysis.

## Hardware Diagnostic — May 2026 (Findings 23-26)

After establishing the upstream-blocked status above, we ran three
standalone SpMV/CG benchmarks **outside the OpenFOAM stack** to
distinguish hardware/runtime issues from software bugs. All three
consumed the same 1M × 1M Poisson 5-point stencil on the same B70.

| Question | Answer | Source |
|---|---|---|
| Is the AMG wall a hardware bug? | **No.** B70 + oneAPI 2025.3 + SYCL is functional for sparse linear algebra. | [Finding 23](findings/23_b70_hardware_functional_amg_wall_is_software.md) |
| How close to peak does PETSc aijkokkos SpMV get? | 79 % of Triad-measured BW (418 GB/s, 0.287 ms/iter on 1M unknowns) | [Finding 24](findings/24_petsc_aijkokkos_spmv_79_percent_triad.md) |
| How does Ginkgo's dpcpp backend compare on the same hardware? | 3.2× faster on pure SpMV microbenchmark (0.089 ms/iter, cache-resident x) | [Finding 25](findings/25_ginkgo_3x_faster_microbench.md) |
| Was the strategic miscall hardware or software? | Software-stack maturity for `aijkokkos+GAMG+SYCL`, **not** Battlemage hardware | [Finding 23](findings/23_b70_hardware_functional_amg_wall_is_software.md) |

The 3.2× SpMV gap to Ginkgo is a microbenchmark with cache-resident
vectors, not a production verdict. See [the sister
repo](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)
for the orthogonal Ginkgo solver-stability picture that determines
whether this microbenchmark advantage translates to a real CFD speedup.

When you reproduce, expect **45–90 min** of build time on a 24-core
machine after Plan I is in place. From scratch (downloads + retries) the
13-iteration discovery process took ≈ 4 hours, and the β5/β5h/F1/F-PRE
exploration on top added another ≈ 6 hours. This repo cuts the entire
journey to ≈ 1 hour by handing you β5h2 directly.

*Pioneer documentation independently maintained.*
*Full reproducibility intended for the next Battlemage CFD pioneer.*
