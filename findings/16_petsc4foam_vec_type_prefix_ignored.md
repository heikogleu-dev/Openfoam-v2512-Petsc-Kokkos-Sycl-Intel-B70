# petsc4Foam's `-eqn_*_vec_type` is Ignored by PETSc

## Summary

petsc4Foam scopes per-equation options by prefixing them with
`-eqn_<field>_` (e.g. `-eqn_p_mat_type`, `-eqn_p_ksp_type`). PETSc
accepts the prefix for KSP/PC/Mat options but **not for `-vec_type`**.
Result: `vec_type kokkos` set in fvSolution silently has no effect.
Vectors stay on the host.

## Symptom

`-log_view` at end of run shows:

```
WARNING! There are options you set that were not used!
WARNING! could be spelling mistake, etc!
There is one unused database option. It is:
Option left: name:-eqn_p_vec_type value: kokkos source: code
```

while the matrix-type counterpart goes through cleanly:

```
-eqn_p_mat_type aijkokkos # (source: code)
```

The PETSc options database silently drops `-eqn_p_vec_type`.

## Why

`PetscObjectSetOptionsPrefix()` sets the prefix used when looking up
`KSPSetFromOptions()`, `MatSetFromOptions()`, etc. PETSc's vector type
selection happens through `VecSetType()` which is invoked at vector
creation, **before** any prefix-aware option lookup runs. So when
PETSc creates the working vectors for the KSP, the `-eqn_p_vec_type`
option isn't queried.

In contrast, `-mat_type` is read by `MatSetFromOptions()` which IS called
with the prefix-aware lookup path on the assembled matrix object.

## Workaround

Set the option **without** the prefix in `PETSC_OPTIONS` env var or
`~/.petscrc`, so it applies globally to all vector creation:

```bash
export PETSC_OPTIONS="-use_gpu_aware_mpi 0 -vec_type kokkos"
```

Caveat: this affects **all** vectors in the run, including ones created
by other PETSc-backed solvers if you have any. For a single-equation
PETSc-on-p configuration this is fine.

## Impact

Without `vec_type kokkos`, the Krylov vectors live in host memory.
`KSPSolve` then alternates host-vector ops (`VecAXPY`, `VecNorm`,
`VecTDot`) with device-side `MatMult` (if `aijkokkos` triggered SYCL
compute, which it didn't here for other reasons — see
[15](15_hypre_um_not_real_gpu_pc.md) and [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md)).

Even if Hypre's BoomerAMG ran on the GPU, mismatched vec_type would
force device→host transfers on every PCApply.

## Reproduction

In `system/fvSolution`:

```
p
{
    solver petsc;
    petsc {
        options {
            mat_type  aijkokkos;
            vec_type  kokkos;
        }
    }
}
```

Run with `-log_view`. Grep the output:

```bash
grep "Option left" log
# Option left: name:-eqn_p_vec_type value: kokkos source: code
```

## Upstream filing plan

To file with petsc4Foam (ESI external-solver):
> The dictionary-driven options are scoped per-equation via
> `PetscObjectSetOptionsPrefix("eqn_<field>_")`. Vector type cannot be
> set this way; consider injecting a non-prefixed `-vec_type` into the
> PETSc options database when the user requests `vec_type` in the dict,
> or document that `-vec_type` must be set globally via PETSC_OPTIONS.

## Status / Resolution

**Workaround documented**, no upstream fix yet.

## Related

- [15](15_hypre_um_not_real_gpu_pc.md) — Hypre BoomerAMG on CPU regardless of vec_type
- [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) — full chain
- ESI petsc4Foam tutorials — none of them request `vec_type`, so this gap goes unnoticed in upstream tests
