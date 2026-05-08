# KokkosKernels Batched GEMM violates SYCL strict-spec — kernel param not trivially copyable

## Summary

KokkosKernels 5.1.0 has a Functor in
`KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp` that holds a non-const
reference member. SYCL 2020 requires kernel parameters to be trivially
copyable; icpx 2025.3+ enforces this strictly. The same defect is present
on `develop` and `master` of KokkosKernels — not yet fixed upstream.

## Symptom

```
KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp:229:54: error:
    'Kokkos::Impl::ParallelFor<(lambda at .../BatchedDblBufGemm)<...>'
    cannot be used as the type of a kernel parameter
        Kokkos::parallel_for("KokkosBatched::BatchedDblBufGemm",
                                                              ^
KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp:198:31: note:
    'BatchedDblBufGemm<...>' is not trivially copyable; field 'ei_'
    of reference type '... &' makes it not trivially copyable
        BatchedDblBufGemm &ei_;
                            ^
```

Offending line excerpt (KokkosKernels 5.1.0):

```cpp
// batched/dense/impl/KokkosBatched_HostLevel_Gemm_DblBuf_Impl.hpp:198
struct Functor {
    BatchedDblBufGemm &ei_;          // <-- reference member
    KOKKOS_INLINE_FUNCTION
    void operator()(const MemberType &member) const { ... }
};
```

## Fix attempts (all rejected)

1. Patch `&ei_` → pointer member: ripples through ~200 call sites.
2. Replace with copy-by-value: object is large, captures Views.
3. Wait for upstream patch: not landed in `master` as of 2026-05.

## Working approach

Disable the Batched component entirely (see findings 08 + 12). KokkosKernels
SPARSE/GRAPH/COMMON are sufficient for PETSc's `aijkokkos` backend after the
`aijkok.kokkos.cxx` patch documented in `12_aijkok_kokkosbatched_dependency.md`.

## Why it happens

Earlier icpx releases (≤ 2024.2) accepted reference members in kernel
parameters as a relaxation. SYCL 2020 §4.12.4 mandates the trivially-copyable
constraint; icpx 2025.3.x enforces it with a hard error
(`-fsycl-host-compiler-options="..."` cannot soften it).

## Impact

| Compiler                    | Build with KK BATCHED on | Notes |
|-----------------------------|--------------------------|-------|
| icpx 2025.3.3.20260319      | FAIL                     | hard error |
| icpx 2026.0.0.20260331      | FAIL                     | identical message |
| g++ 15.x (CPU-only Kokkos)  | OK                       | no SYCL constraint |
| KokkosKernels 5.1.0 master  | FAIL                     | unfixed upstream |

## Status / Resolution

Backend / upstream defect. Mitigation = disable BATCHED component
(see `08`, `12`). See `../patches/plan-i.patch` for the full patch set.

## Related

- `08_kk_components_force_batched_via_sparse.md` — disabling BATCHED is
  harder than expected
- `12_aijkok_kokkosbatched_dependency.md` — PETSc's hidden dependency
