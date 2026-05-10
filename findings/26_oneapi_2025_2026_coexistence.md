# oneAPI 2025.3 and 2026.0 Coexist on the Same Workstation

## Summary

PETSc β5h2 is built and linked against oneAPI 2025.3.3 (`libsycl.so.8`).
Ginkgo at `/opt/ginkgo` is built and linked against oneAPI 2026.0
(`libsycl.so.9`). Both run on the same B70 hardware, in the same
session, without conflict — provided each is launched with the matching
`setvars.sh` for its build version.

## Observation

The naive build attempt:

```bash
source /opt/intel/oneapi/2025.3/setvars.sh
icpx -fsycl ... -L/opt/ginkgo/lib -lginkgo_dpcpp ... test3b.cpp
# /opt/ginkgo/lib/libginkgo.so needs libsycl.so.9 (2026.0)
# /opt/intel/oneapi/2025.3/compiler/2025.3/lib/libsycl.so.8 is current PATH
# linker pulls libsycl.so.9 from somewhere (LD_LIBRARY_PATH residue?)
# undefined references to ur*Exp@LIBUR_LOADER_0.12
```

The fix:

```bash
# Source the matching oneAPI for the dependency you are linking against
source /opt/intel/oneapi/setvars.sh   # → 2026.0 (default symlink)
icpx -fsycl ... -L/opt/ginkgo/lib -lginkgo_dpcpp ... test3b.cpp  # works
```

## Why This Matters Practically

- A workstation can host both stacks without virtual environments,
  containers, or chroots
- Switching between stacks is `source X.../setvars.sh` — no system-wide
  state to manage
- Mixing within a single binary (linking against both PETSc and Ginkgo
  in the same executable) would require building both against the same
  oneAPI version; this was not attempted

## Implication

For diagnostic and benchmark work, two parallel CFD GPU stacks on B70
is feasible. For production deployment of a single binary, pick one
oneAPI version and rebuild any external dependency consistently.

## Status / Resolution

**Observation logged.** No action required — coexistence is the natural
state of side-by-side oneAPI installations.

## Related

- [10](10_oneapi_2026_dpct_2025_3_mismatch.md) — earlier note on why
  2025.3 was selected for PETSc/Hypre; that decision stands
- [25](25_ginkgo_3x_faster_microbench.md) — used this coexistence to
  benchmark across stacks
