# Legacy `/usr/bin/ocloc` cannot AOT-compile for Battlemage — drop AOT, use JIT

## Summary

The Ubuntu 26.04 archive ships `intel-ocloc 24.35.30872.45-1` (held back from
upgrades by a CR-pin on this machine). That `ocloc` predates Battlemage and
its `compile -device` accepts only Gen9–Gen11 / DG1 / ATS targets — no
`bmg_g31`. icpx 2026's flag `-fsycl-targets=intel_gpu_bmg_g31` shells out to
`/usr/bin/ocloc` and fails. Workaround: omit `-fsycl-targets`, let SPIR-V
JIT through the modern `libze-intel-gpu1 26.05.37020.3` runtime which knows
B70 natively.

## Symptom

```
$ icpx -fsycl -fsycl-targets=intel_gpu_bmg_g31 -c probe.cpp
icpx: error: gen compiler command failed with exit code 1 (use -v to see invocation)
ocloc: Could not determine device target: bmg_g31.
       Available devices: skl, kbl, cfl, icllp, tgllp, ehl, dg1, adl-s, adl-p, ats-m150
```

Confirm the legacy binary:

```
$ /usr/bin/ocloc --version
Intel(R) oneAPI Level Zero Compiler 24.35.30872.45 (rev. 1)
$ apt-cache policy intel-ocloc | head -3
intel-ocloc:
  Installed: 24.35.30872.45-1
  Candidate: 24.35.30872.45-1
```

While the modern Level-Zero runtime knows the GPU:

```
$ sycl-ls
[opencl:gpu] Intel(R) Arc(TM) Pro B70 Graphics 24.85.7 [OpenCL 3.0 NEO]
[level_zero:gpu] Intel(R) Arc(TM) Pro B70 Graphics 1.6 [1.6.37020]
```

## Fix

Drop AOT entirely; PETSc configure uses JIT-only SYCL:

```bash
./configure \
    --with-sycl=1 \
    --with-sycl-dir=/opt/intel/oneapi/2025.3/compiler/2025.3 \
    --SYCLOPTFLAGS='-O3' \
    --SYCLFLAGS='-fsycl'      # no -fsycl-targets=...
```

First kernel launch JITs SPIR-V → IGC → bmg_g31 binary in `~ZE_CACHE_DIR`,
TTL persistent across runs:

```bash
export NEO_CACHE_PERSISTENT=1
export NEO_CACHE_DIR=$HOME/.cache/neo_compiler_cache
```

## Why it happens

`ocloc` and the Level-Zero compute runtime are in two different Debian
packages with different release cadences. The CR-pin keeps `ocloc` at the
old LTS pin while the runtime advanced. Mixing AOT (`ocloc`-driven) with a
modern runtime is unsupported.

## Impact

| Path        | Outcome                                       |
|-------------|-----------------------------------------------|
| AOT bmg_g31 | broken (legacy ocloc)                          |
| AOT pvc     | works but wrong target                        |
| JIT SPIR-V  | works, +0.5–2 s first-run cache miss per kernel |

After the cache is warm, JIT cost is zero. Production CFD runs are
single-shot per case anyway.

## Status / Resolution

Worked around at the configure level (no AOT). Upstream fix would need
`intel-ocloc >= 25.x`; CR-pin has higher priority for now.

## Related

- `07_kk_batched_sycl_strict_spec.md` — next SYCL roadblock
- `14_ex3k_igc_compiler_error_battlemage.md` — IGC bug surfacing under JIT
