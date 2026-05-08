# Plan I Patch Documentation

[`plan-i.patch`](plan-i.patch) is a **documentation file** — not a
machine-applicable unified diff. It describes the source-level changes
needed to bring up PETSc 3.25.1 + KokkosKernels 5.1.0 + Hypre develop
on Intel Arc Pro B70 Pro under oneAPI 2025.3.3.

## What's Patched

| File (in upstream tree) | Change | Why |
|---|---|---|
| `kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake` | comment-out 3 `set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)` lines (in the SPARSE, GRAPH, and ALL_COMPONENTS conditional blocks) | KokkosKernels' own CMake unconditionally re-enables BATCHED whenever SPARSE is requested, defeating any user-supplied `-DKK_ENABLE_BATCHED=OFF`. We need SPARSE for `aijkokkos`; we need BATCHED off because of [findings/07](../findings/07_kk_batched_sycl_strict_spec.md). The patch decouples them. See [findings/08](../findings/08_kk_components_force_batched_via_sparse.md). |
| `petsc-3.25.1/src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx` | comment 2 `KokkosBatched_*Decl.hpp` includes; replace `MatInvertVariableBlockDiagonal_SeqAIJKokkos` body with `SETERRQ` stub | PETSc's `aijkok.kokkos.cxx` would otherwise fail to compile with KokkosKernels-without-BATCHED. Only one PC (VPB-Jacobi for Kokkos matrices) is impacted, and we don't use it. See [findings/12](../findings/12_aijkok_kokkosbatched_dependency.md). |

## Two Files NOT Patched (Despite Mentioning KokkosBatched)

- `petsc-3.25.1/src/ksp/pc/impls/bjacobi/bjkokkos/bjkokkoskernels.kokkos.cxx` —
  entirely wrapped in `#if defined(PETSC_HAVE_KOKKOS_KERNELS_BATCH)`, a
  macro that is **not** set in our build, so the file compiles to a no-op.
- `petsc-3.25.1/src/ml/da/impls/ensemble/letkf/kokkos/letkf_local_analysis.kokkos.cxx` —
  mentions "KokkosBatched" only in a comment string at line 678; no actual
  symbol use.

## Reproducibility Path

The Stufe-2 build script ([`scripts/stufe2-petsc.sh`](../scripts/stufe2-petsc.sh))
applies the `aijkok.kokkos.cxx` patch idempotently (skipped if already
applied). The KokkosKernels patch must be applied to a local tarball
**before** PETSc configure runs, because PETSc git-clones `git.kokkos-kernels`
otherwise. See [findings/09](../findings/09_petsc_local_tarball_file_url.md)
for why we use `--download-kokkos-kernels=file:///path/to/local-patched.tar.gz`.

The build script does this prep step for you, but if you set up the
KokkosKernels tarball manually:

```bash
cd /opt/openfoam-v2512/tarballs
wget https://github.com/kokkos/kokkos-kernels/archive/refs/tags/5.1.0.tar.gz
tar xzf 5.1.0.tar.gz
sed -i 's|^  set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)$|  # Plan I disabled (was: \0)|' \
  kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake
tar czf kokkos-kernels-5.1.0-plan-i.tar.gz kokkos-kernels-5.1.0
```

## License Note

These patches are **derivative works** of:
- KokkosKernels (BSD-3-Clause, SNL)
- PETSc (BSD-2-Clause, ANL)

The *prose describing the patches* (this README, `plan-i.patch`) is GPL-3.0
(this repository's own work). The *code changes themselves*, when applied to
your local tree, remain under each upstream's BSD license — BSD permits
modification with attribution preserved.

See [NOTICE.md](../NOTICE.md) for the full attribution map.

## Upstream Filing Plan

When upstream-able, both fixes will be filed:

1. **KokkosKernels:** propose decoupling SPARSE → BATCHED in
   `kokkoskernels_components.cmake`, possibly with a "BATCHED required for
   SPARSE-block-row support" doc note. The `BatchedDblBufGemm` reference
   member in line 229 of `KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp`
   should also be rewritten as a pointer to satisfy strict SYCL spec.
2. **PETSc:** wrap `aijkok.kokkos.cxx`'s `KokkosBatched_*` includes and
   the `MatInvertVariableBlockDiagonal_SeqAIJKokkos` function in a
   `#if defined(PETSC_HAVE_KOKKOS_KERNELS_BATCHED)` guard, mirroring the
   pattern already used in `bjkokkoskernels.kokkos.cxx`.

Status of each: see [references.md](../references.md#bug-filing-status).
