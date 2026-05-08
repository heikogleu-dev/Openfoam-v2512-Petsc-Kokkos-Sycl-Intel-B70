# Plan I Iteration Journal

Chronological list of every failed configure/build/run attempt and the
fix applied. Useful for predicting which errors a fresh reproducer will
hit and in which order. All findings are cross-linked.

Each row shows: which iteration # (in time order), what failed, the fix
applied, and the resulting cumulative state.

| # | Failure | Fix | Resulting State |
|---|---|---|---|
| 1 | Stufe 1 apt: `libparmetis-dev` not found in U26.04 | swap → `libscotchparmetis-dev` ([01](../findings/01_libparmetis_replaced_libscotchparmetis_u26.md)) | apt install OK |
| 2 | Stufe 1 ESI git-clone: `develop.openfoam.com` requires login (302 → /sign_in) | tarball mirror `dl.openfoam.com/source/v2512/` ([03](../findings/03_esi_repo_login_required_tarball_fallback.md)) | sources fetched |
| 3 | Stufe 1 ThirdParty: scotch_6.1.0 fails to compile under GCC 15 (K&R prototypes) | switch ESI to system-scotch via `etc/config.sh/scotch` ([02](../findings/02_scotch_6_1_0_gcc15_strict_prototype.md)) | Stufe 1 GO |
| 4 | Stufe 1+2 shell: `set -u` exits in non-interactive bash on OpenFOAM bashrc:184 | drop global `-u`, keep `-o pipefail` ([04](../findings/04_set_u_bashrc_184_unbound.md)) | scripts robust |
| 5 | PETSc configure: `Bad linker flag: -fsycl` rejected by mpicxx (which wraps g++) | force `/usr/bin/mpicxx` + `OMPI_CXX=icpx` ([05](../findings/05_oneapi_intel_mpi_path_priority.md)) | linker path correct |
| 6 | PETSc configure SYCL test: `Could not determine device target: bmg_g31` from `/usr/bin/ocloc 24.35` | drop `-fsycl-targets=intel_gpu_bmg_g31`, JIT only ([06](../findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md)) | SYCL compile passes |
| 7 | PETSc configure: KokkosKernels build fails on `BatchedDblBufGemm` SYCL strict spec violation | initially → `--with-kokkos-kernels=0` (later refined) | configure runs further |
| 8 | PETSc make check: `Unknown Mat type given: aijkokkos` (KK disabled killed `aijkok` build) | re-enable KokkosKernels but with BATCHED off | hits next layer |
| 9 | KokkosKernels CMake: `BATCHED:ON` despite `-DKK_ENABLE_BATCHED=OFF` (SPARSE/GRAPH/ALL force it) | patch `kokkoskernels_components.cmake` ([08](../findings/08_kk_components_force_batched_via_sparse.md)) | requires source edit |
| 10 | PETSc git-clones KK and overwrites our patch | use local pre-patched tarball + `file://` URL ([09](../findings/09_petsc_local_tarball_file_url.md)) | KK patches survive |
| 11 | KK build OK, but `aijkok.kokkos.cxx` fails to compile (KokkosBatched_*Decl.hpp missing) | patch aijkok: comment includes + SETERRQ stub for VPB-Jacobi ([12](../findings/12_aijkok_kokkosbatched_dependency.md)) | aijkok compiles |
| 12 | Hypre release fails on DPCT-2025.3-vs-icpx-2026 mismatch (`get_tangle_group` removed) | initial: `--download-hypre-commit=origin/master` (Plan E) | hypre OK on 2026 |
| 13 | Plan H: switch to oneAPI 2025.3.3 (PMZFX-validated), Hypre release tried again | release Hypre still fails on DPL `dpct::constant_iterator` ctor under 2025.3 | revert to Hypre master ([11](../findings/11_hypre_master_required.md)) |
| 14 | Phase 6 ex2: `symbol urDeviceWaitExp not found` (binary linked against 2026 libsycl) | `rm ex2 && make ex2` to relink against 2025.3 | ex2 starts |
| 15 | Phase 6 ex2 GPU run: `MPI is not aware of sycl GPU devices` (rc 76) | add `-use_gpu_aware_mpi 0` ([13](../findings/13_use_gpu_aware_mpi_off.md)) | ex2 starts solver |
| 16 | Phase 6 ex2 GPU run: `Unknown option "l1-Jacobi"` (Hypre master renamed it) | `l1scaled-jacobi` ([11](../findings/11_hypre_master_required.md)) | **GPU sanity converges, Stufe 2 GO** |
| (17) | Phase 5 make check: `ex3k aijkokkos+ILU0` fails with IGC ICE | tolerate; ex19+HYPRE pass is sufficient ([14](../findings/14_ex3k_igc_compiler_error_battlemage.md)) | known backend bug |

## Total Time

- Discovery (iterations 1–17, with several restarts and downloads):
  ≈ 4 hours wall-clock on a 24-core / 96 GB / 800 Mbps machine
- Reproduction (Plan I in place from the start, this repo's scripts):
  ≈ 60–90 minutes

## Two Key Decision Points

### A) oneAPI 2026 vs 2025.3.3

Switching to 2025.3.3 (Plan H) was the most strategic choice. With 2026 we
had to chase Hypre's DPL/DPCT mismatch upstream into Hypre master, and KK's
BatchedDblBufGemm spec issue **also** appears under 2026 (it's not a
2026-versus-2025 problem; it's the SYCL strict spec from icpx 2025.3+).

Net: **2025.3.3 stack works AND is what PMZFX validated** ([references.md](../references.md)).
2026 would only have been required if we needed ABI stability with
ParaView 6.1.0 (which we don't here).

### B) Hypre master vs Hypre release

Even on 2025.3, Hypre release fails on `dpct::constant_iterator`. The fix
is upstream master. We pin `--download-hypre-commit=origin/master` to get
a moving target — accepted risk for now; will pin a specific SHA when
Hypre tags a fixed release.

## What This Journal Replaces

This is a deliberately concise sequential record. The full per-iteration
session transcripts (with command outputs, complete error stacks, and the
14 intermediate failed configures) totaled ≈ 250 KB across 5 PETSc
configure runs. The trimmed [`stufe2-master.log`](stufe2-master.log) is
the GO-run only.
