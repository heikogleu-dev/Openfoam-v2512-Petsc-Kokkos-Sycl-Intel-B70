# References

## Upstream Projects

### PETSc / petsc4Foam
- [petsc/petsc](https://gitlab.com/petsc/petsc) — Portable Extensible Toolkit
  for Scientific Computing (BSD-2-Clause)
- [PETSc 3.25 Release Notes](https://petsc.org/main/changes/) — for context on
  Kokkos / SYCL backend status as of May 2026
- [hpsim/petsc4Foam](https://gitlab.com/hpsim/petsc4Foam) — PETSc adapter for
  OpenFOAM; the Stufe-3 integration target
- **Behrendt et al. 2024** — *PETSc4Foam: A Library to plug-in PETSc into the
  OpenFOAM Framework*, Wiley CCPE
  [doi:10.1002/cpe.7521](https://doi.org/10.1002/cpe.7521)

### Hypre / BoomerAMG
- [hypre-space/hypre](https://github.com/hypre-space/hypre) — High-performance
  preconditioners and solvers (Apache-2.0 / MIT dual)
- The `develop` (master) branch as of May 2026 contains the DPL / DPCT fix
  needed for icpx 2025.3 + (see [findings/11](findings/11_hypre_master_required.md)).
  Fix expected to land in next Hypre release.
- **Falgout et al. 2002** — *hypre: a Library of High Performance
  Preconditioners*, ICCS — original BoomerAMG reference
- **Yang & Mittal 2024** — *Algebraic Multigrid for Heterogeneous Architectures*,
  SIAM J. Sci. Comput. — relevant for `--enable-unified-memory` build mode

### Kokkos / KokkosKernels
- [kokkos/kokkos](https://github.com/kokkos/kokkos) — performance-portable
  C++ programming model (BSD-3-Clause / SNL)
- [kokkos/kokkos-kernels](https://github.com/kokkos/kokkos-kernels) — sparse
  / dense linear algebra; we use 5.1.0 with [BATCHED component disabled](findings/08_kk_components_force_batched_via_sparse.md)
- KokkosKernels **issue to file (not yet upstreamed):**
  `BatchedDblBufGemm<...>::Functor` holds `BatchedDblBufGemm &ei_;` as a
  reference member. SYCL strict spec rejects non-trivially-copyable types
  as kernel parameters. Either rewrite as `*ei_` pointer or guard the
  ETI for SYCL backend. See [findings/07](findings/07_kk_batched_sycl_strict_spec.md).
- **Trott et al. 2022** — *Kokkos 3: Programming Model Extensions for the
  Exascale Era*, IEEE TPDS [doi:10.1109/TPDS.2021.3097283](https://doi.org/10.1109/TPDS.2021.3097283)

### Umpire / Caliper
- [LLNL/Umpire](https://github.com/LLNL/Umpire) — memory pool allocator
  (BSD-3-Clause LLNL-CODE)
- [LLNL/Caliper](https://github.com/LLNL/Caliper) — profiling instrumentation
  (BSD-3-Clause LLNL-CODE)

### OpenFOAM
- [ESI OpenFOAM (OpenCFD Ltd.)](https://www.openfoam.com) — v2512 used in Stufe 1
- [Foundation OpenFOAM](https://openfoam.org) — v13 line; coexists at `/opt/openfoam13/`
- [Tarballs mirror `dl.openfoam.com`](https://dl.openfoam.com/source/v2512/) —
  source location after `develop.openfoam.com` repo privatization (see
  [findings/03](findings/03_esi_repo_login_required_tarball_fallback.md))

### Intel oneAPI / Compute Runtime / Level Zero
- [Intel oneAPI Base Toolkit Download](https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit-download.html) —
  use **2025.3** for B70/Battlemage; 2026 has DPCT deprecated (see
  [findings/10](findings/10_oneapi_2026_dpct_2025_3_mismatch.md))
- [intel/compute-runtime](https://github.com/intel/compute-runtime) — NEO
  (MIT). CR `26.05.37020.3` is **pinned** on this system; later versions
  break multi-rank workloads on Battlemage (see sister repo finding 13)
- [oneapi-src/level-zero](https://github.com/oneapi-src/level-zero) — L0
  loader (MIT)
- [Intel oneAPI 2026 Release Notes](https://www.intel.com/content/www/us/en/developer/articles/release-notes/intel-oneapi-toolkit-release-notes.html) —
  documents DPCT deprecation

## Reference Pioneer Repositories on B70

- **[PMZFX/intel-arc-pro-b70-benchmarks](https://github.com/PMZFX/intel-arc-pro-b70-benchmarks)** —
  llama.cpp SYCL + Vulkan + vLLM XPU benchmarks. Documents oneAPI 2025.3+
  as the validated stack for B70 LLM inference. Their hardware-validation
  is what convinced us to switch from oneAPI 2026 to 2025.3 in
  [findings/10](findings/10_oneapi_2026_dpct_2025_3_mismatch.md).

- **[Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes](https://github.com/Hal9000AIML/arc-pro-b70-ubuntu-gpu-speedup-bugfixes)** —
  Ubuntu/B70 driver workarounds: 11 llama.cpp cherry-picks, Mesa 26
  patches, runtime env workarounds. Confirms the broader Battlemage
  ecosystem still needs targeted fixes per workload.

- **[heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)** —
  sister repo: Foundation OF13 + OGL + Ginkgo. Demonstrated the failure
  modes of Ginkgo 1.10/1.11 on Battlemage SYCL, motivating the PETSc+Hypre
  alternative documented here.

## HPC Centres Running PETSc + Kokkos + SYCL on Intel GPUs (Aurora-class)

- **Argonne National Laboratory — Aurora Exascale System** — Intel Xe-HPC
  (PVC) production stack. Same PETSc + Kokkos + SYCL software pattern,
  validated at scale. References:
  - [Aurora Documentation: PETSc on Intel GPUs](https://docs.alcf.anl.gov/aurora/programming-models/oneapi-mkl/)
  - Aurora-class systems use Intel oneAPI versions in lock-step with
    DPCT — same reason we pin 2025.3 here.

## Related Phoronix / Press Coverage

- [Intel Arc Pro B70 Open-Source Linux Performance — Phoronix Review](https://www.phoronix.com/review/intel-arc-pro-b70/) —
  reference benchmarks for non-CFD workloads on the same hardware
  (rendering, video, ML inference)

## Hypre Master / Develop Branch Status

As of May 2026, Hypre's master branch contains the fixes for:
- DPL `dpct::constant_iterator<int>` constructor mismatch under oneAPI 2025.3
- Removal of stale `get_tangle_group` / `get_fixed_size_group` references

The next Hypre tagged release (anticipated mid-2026) will likely include
these. Until then, this repo pins `--download-hypre-commit=origin/master`.

## Bug Filing Status

| Bug | Project | Status |
|---|---|---|
| `BatchedDblBufGemm` reference member rejected by SYCL strict spec | KokkosKernels | **Not yet filed** — fix candidate documented in [findings/07](findings/07_kk_batched_sycl_strict_spec.md); intended for upstream Kokkos issue tracker |
| KK CMake `SPARSE → BATCHED FORCE-on` regardless of `ENABLE_BATCHED=OFF` | KokkosKernels | **Not yet filed** — workaround in [findings/08](findings/08_kk_components_force_batched_via_sparse.md); we suggest decoupling SPARSE↔BATCHED |
| Legacy `/usr/bin/ocloc 24.35` doesn't recognise Battlemage device-name `bmg_g31` | Intel CR / IGC | **Not filed** — upstream NEO already supports BMG in 26.05; user-side simply uses JIT |
| `aijkok.kokkos.cxx` hard dependency on KokkosBatched headers | PETSc | **Not yet filed** — upstream might want to `#if defined(PETSC_HAVE_KOKKOS_KERNELS_BATCHED)` guard the section, mirroring `bjkokkoskernels` |

When we file these, the issue bodies will be added under [findings/](findings/)
following the sister repo's `*_issue_body.md` convention.
