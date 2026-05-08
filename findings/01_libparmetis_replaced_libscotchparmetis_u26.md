# libparmetis-dev removed in Ubuntu 26.04 — replace with libscotchparmetis-dev

## Summary

Ubuntu 26.04 LTS no longer ships `libparmetis-dev` in the main archive.
ESI OpenFOAM v2512's `Allwmake` step pulls it via apt and aborts on the first
missing-package error. Trivial swap to the Scotch-based ParMETIS interface
fixes it; ABI-compatible for OpenFOAM's decomposition libs.

## Symptom

```
$ sudo apt install libparmetis-dev
Reading package lists... Done
Building dependency tree... Done
E: Unable to locate package libparmetis-dev
E: Couldn't find any package by glob 'libparmetis-dev'
```

`apt-cache search` confirms the upstream-suggested replacement:

```
$ apt-cache search parmetis
libscotchparmetis-dev - parallel graph partitioning - ParMETIS-compat dev files
libscotchparmetis-8.0 - parallel graph partitioning - ParMETIS-compat runtime
```

## Fix

```bash
sudo apt install --no-install-recommends \
    libscotch-dev libscotchparmetis-dev libptscotch-dev \
    libmetis-dev libcgal-dev libfftw3-dev libboost-system-dev \
    flex bison m4 zlib1g-dev libreadline-dev
```

Verify the headers expose the standard ParMETIS API:

```
$ dpkg -L libscotchparmetis-dev | grep -E '\.h$'
/usr/include/parmetis.h
```

OpenFOAM's `wmake` looks for `parmetis.h`, finds the Scotch shim, links
`-lscotchparmetis` instead of `-lparmetis`. No source patch required.

## Why it happens

Debian/Ubuntu dropped the original Karypis ParMETIS due to non-DFSG license
clauses (no-redistribution-without-permission). `libscotchparmetis-dev`
ships an API-compatible re-implementation under CeCILL-C and is now the
default provider of `parmetis.h` in the Ubuntu archive.

## Impact

| Component                      | Status |
|--------------------------------|--------|
| `scotchDecomp`                 | OK |
| `ptscotchDecomp`               | OK |
| `metisDecomp`                  | OK (uses real `libmetis-dev`) |
| `decomposePar -method scotch`  | OK |
| `decomposePar -method ptscotch`| OK |

## Status / Resolution

Fixed by package substitution at the apt level; no code change required.

## Related

- `02_scotch_6_1_0_gcc15_strict_prototype.md` — Scotch bundled in
  ThirdParty fails to build under GCC 15; same component reached differently
- `03_esi_repo_login_required_tarball_fallback.md` — source acquisition
