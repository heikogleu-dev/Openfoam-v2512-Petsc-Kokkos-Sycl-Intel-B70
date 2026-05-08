# Build Configurations

| File | Purpose |
|---|---|
| [`petsc-configure-bmg-opt.sh`](petsc-configure-bmg-opt.sh) | Reference PETSc 3.25.1 configure invocation under Plan I — extracted from [`scripts/stufe2-petsc.sh`](../scripts/stufe2-petsc.sh) for standalone reference and audit |

## Why a separate file?

The full Stufe-2 build script generates this configure invocation
on-the-fly (so paths can be resolved against env vars). Pinning it in
`configs/` makes it easy to **diff** against future PETSc versions or
oneAPI updates: any change to one of the flags becomes a one-line audit.

## Notable Plan I flags (each maps to one finding)

```
--with-cc=/usr/bin/mpicc           # findings/05 (force sys-OpenMPI vs Intel-MPI)
--with-cxx=/usr/bin/mpicxx
--SYCLFLAGS='-fsycl'               # findings/06 (NO -fsycl-targets, JIT only)
--download-kokkos-kernels=file://… # findings/09 (file:// prefix to bypass git fallback)
--download-hypre-commit=origin/master  # findings/11 (release Hypre fails on DPL)
--download-hypre-configure-arguments='--enable-unified-memory'  # USM mode
```

Plus the env vars:
- `OMPI_CC=icx`, `OMPI_CXX=icpx` — System-OpenMPI's mpicc/mpicxx wrappers
  use icx/icpx underneath, so `-fsycl` is understood at link
- `MKLROOT` — set by sourcing `/opt/intel/oneapi/2025.3/setvars.sh`
