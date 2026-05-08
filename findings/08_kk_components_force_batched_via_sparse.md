# KokkosKernels SPARSE forces BATCHED back ON — patch components.cmake

## Summary

Setting `-DKokkosKernels_ENABLE_COMPONENT_BATCHED=OFF` does not actually
disable the BATCHED component. `cmake/kokkoskernels_components.cmake`
re-enables it via three `FORCE`-set CACHE writes triggered by SPARSE,
GRAPH, or ALL_COMPONENTS. Comment-out those three lines (or all-components
patch) to make the user-facing flag take effect.

## Symptom

PETSc configures with KokkosKernels and `BATCHED=OFF`:

```
$ cmake -DKokkosKernels_ENABLE_COMPONENT_BATCHED=OFF \
        -DKokkosKernels_ENABLE_COMPONENT_SPARSE=ON  ... ..
-- Kokkos Kernels components: BATCHED;BLAS;COMMON;GRAPH;LAPACK;ODE;SPARSE
                              ^^^^^^^ still on
```

After build, the failing TUs from finding 07 still appear:

```
KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp:229:54: error: ... cannot be used
as the type of a kernel parameter
```

## Root cause

```cmake
# kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake (excerpt)
if (KokkosKernels_ENABLE_COMPONENT_SPARSE)
    # Sparse depends on everything else so no real benefit here unfortunately...
    set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
    set(KokkosKernels_ENABLE_COMPONENT_BLAS    ON CACHE BOOL "" FORCE)
    set(KokkosKernels_ENABLE_COMPONENT_GRAPH   ON CACHE BOOL "" FORCE)
endif()
if (KokkosKernels_ENABLE_COMPONENT_GRAPH)
    set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
    ...
endif()
if (KokkosKernels_ENABLE_ALL_COMPONENTS)
    set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
    ...
endif()
```

`FORCE` overwrites whatever the user passed on the command line.

## Fix

Patch the three sites. Diff (excerpt, full text in
`../patches/plan-i.patch`):

```diff
--- a/cmake/kokkoskernels_components.cmake
+++ b/cmake/kokkoskernels_components.cmake
@@ if (KokkosKernels_ENABLE_COMPONENT_SPARSE)
-  set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
+# set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE) # Plan-I
@@ if (KokkosKernels_ENABLE_COMPONENT_GRAPH)
-  set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
+# set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE) # Plan-I
@@ if (KokkosKernels_ENABLE_ALL_COMPONENTS)
-  set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)
+# set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE) # Plan-I
```

Verify after `cmake ..`:

```
-- Kokkos Kernels components: BLAS;COMMON;GRAPH;LAPACK;ODE;SPARSE
                              ^^ no BATCHED
```

## Why it happens

Upstream comment is honest: SPARSE pulls templates from BATCHED for some
TPL paths; the FORCE was a "fail-safe" to avoid linker errors. Our
`aijkokkos` backend in PETSc only uses one BATCHED entry point
(`MatInvertVariableBlockDiagonal_SeqAIJKokkos`) which we stub out
separately (see `12`).

## Impact

- PETSc + KokkosKernels SPARSE/GRAPH builds clean for SYCL bmg_g31.
- VPB-Jacobi PC for `aijkokkos` is gone (SETERRQ stubs return UNSUP).
- All other Kokkos PCs / KSPs unaffected.

## Status / Resolution

Patched in our build. Upstream PR not filed (the comment indicates the
authors know about the coupling).

## Related

- `07_kk_batched_sycl_strict_spec.md` — root SYCL error this avoids
- `09_petsc_local_tarball_file_url.md` — how we get the patched tarball into PETSc
- `12_aijkok_kokkosbatched_dependency.md` — companion source patch
