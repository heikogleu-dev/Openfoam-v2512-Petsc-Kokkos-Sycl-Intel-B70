# PETSc `aijkok.kokkos.cxx` hard-depends on KokkosBatched — patch one function

## Summary

With the BATCHED component disabled in KokkosKernels (finding 08), the
PETSc 3.25.1 file `src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx` no
longer compiles: it includes two KokkosBatched headers and uses
`KokkosBatched::TeamLU` / `TeamInverseLU` in exactly one function,
`MatInvertVariableBlockDiagonal_SeqAIJKokkos` (called by VPB-Jacobi PC for
Kokkos matrices). Comment out the includes and stub the function body
with `SETERRQ`. Two adjacent files were inspected and need no patch.

## Symptom

After applying the KokkosKernels patch (08) and configuring PETSc:

```
src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx:25:10: fatal error:
    'KokkosBatched_LU_Decl.hpp' file not found
   25 | #include <KokkosBatched_LU_Decl.hpp>
      |          ^~~~~~~~~~~~~~~~~~~~~~~~~~~
```

## Patch (excerpt — full diff in `../patches/plan-i.patch`)

```diff
--- a/src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx
+++ b/src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx
@@ -22,8 +22,8 @@
 #include <KokkosSparse_spgemm.hpp>
 #include <KokkosSparse_spadd.hpp>
-#include <KokkosBatched_LU_Decl.hpp>
-#include <KokkosBatched_InverseLU_Decl.hpp>
+// #include <KokkosBatched_LU_Decl.hpp>        // Plan-I: BATCHED off
+// #include <KokkosBatched_InverseLU_Decl.hpp> // Plan-I: BATCHED off

 // ... unchanged ...

@@ static PetscErrorCode MatInvertVariableBlockDiagonal_SeqAIJKokkos(
     Mat A, PetscInt nblocks, const PetscInt *bsizes, PetscScalar *diag)
 {
-    // ~80 lines using KokkosBatched::TeamLU / TeamInverseLU
-    // ...
+    PetscFunctionBegin;
+    SETERRQ(PetscObjectComm((PetscObject)A), PETSC_ERR_SUP,
+        "VPB-Jacobi for SeqAIJKokkos disabled in Plan I patch "
+        "(KokkosKernels BATCHED=OFF for SYCL)");
+    PetscFunctionReturn(PETSC_SUCCESS);
 }
```

## Other files inspected

| File | Verdict |
|------|---------|
| `src/ksp/pc/impls/bjkokkoskernels/bjkokkoskernels.kokkos.cxx` | entire TU under `#if defined(PETSC_HAVE_KOKKOS_KERNELS_BATCH)` — never set in our build, no patch needed |
| `src/dm/impls/network/letkf_local_analysis.kokkos.cxx`        | mentions "KokkosBatched" only in a comment string, no actual include |

## Why it happens

KokkosKernels' BATCHED component is the only home for Team-level LU /
TeamInverseLU. PETSc's "variable point-block Jacobi" preconditioner
specifically uses these. Disabling BATCHED removes the headers; PETSc
TUs that use them must be patched out.

## Impact

| Functionality                                         | After patch |
|-------------------------------------------------------|-------------|
| `aijkokkos` matrix type (creation, MatMult, MatSolve) | OK          |
| `pc_type vpbjacobi` on aijkokkos                      | UNSUP error at runtime (clean, no crash) |
| `pc_type vpbjacobi` on standard aij                   | OK (different code path) |
| All other Kokkos-backed PCs / KSPs                    | OK          |

## Reproduction

```
$ mpirun -np 1 ./ex2 -mat_type aijkokkos -pc_type vpbjacobi
PETSc ERROR: VPB-Jacobi for SeqAIJKokkos disabled in Plan I patch ...
```

## Status / Resolution

Patched in our PETSc tree; carried in `../patches/plan-i.patch`. Drop
once KokkosKernels SYCL strict-spec issue (07) is fixed upstream and
BATCHED can be re-enabled.

## Related

- `07_kk_batched_sycl_strict_spec.md`, `08_kk_components_force_batched_via_sparse.md`
- `09_petsc_local_tarball_file_url.md`
