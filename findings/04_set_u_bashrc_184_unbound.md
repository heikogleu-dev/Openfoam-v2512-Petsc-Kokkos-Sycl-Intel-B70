# OpenFOAM `etc/bashrc` aborts under `set -u` — unbound `WM_PROJECT_DIR`

## Summary

A clean shell launched as `bash --noprofile --norc` with `set -euo pipefail`
exits the moment OpenFOAM's `etc/bashrc` is sourced. Line 184 of the ESI
v2512 bashrc reads `$WM_PROJECT_DIR` to scrub stale paths, but on a fresh
shell that variable is unset. Same defect in Foundation v13's bashrc.
Solution: drop the global `-u`, keep `-o pipefail`, and use defensive
`${var:-}` expansion in our wrapper scripts.

## Symptom

```
$ bash --noprofile --norc
bash$ set -euo pipefail
bash$ source /home/heiko/OpenFOAM/OpenFOAM-v2512/etc/bashrc
/home/heiko/OpenFOAM/OpenFOAM-v2512/etc/bashrc: line 184: WM_PROJECT_DIR: unbound variable
exit
```

Line excerpt:

```bash
# OpenFOAM-v2512/etc/bashrc:182-186
foamOldDirs="$WM_PROJECT_DIR $WM_THIRD_PARTY_DIR \
            $HOME/$WM_PROJECT/$WM_PROJECT_VERSION \
            $HOME/$WM_PROJECT \
            $FOAM_SITE_APPSBIN $FOAM_SITE_LIBBIN"
```

Foundation v13's `/opt/openfoam13/etc/bashrc` has the identical pattern at
line 167.

## Fix

In our setup wrappers (`setup/01_env_esi.sh`, `setup/02_env_petsc.sh`):

```bash
#!/usr/bin/env bash
set -eo pipefail            # NOT -u
# ...
source /home/heiko/OpenFOAM/OpenFOAM-v2512/etc/bashrc
# now -u is safe again if desired
[ -n "${WM_PROJECT_DIR:-}" ] || { echo "OpenFOAM env not loaded" >&2; exit 1; }
```

Defensive expansion for any of our own variables:

```bash
: "${PETSC_DIR:?PETSC_DIR must be set}"
PATH="${PATH:-}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
```

## Why it happens

OpenFOAM's bashrc was written assuming a standard interactive login shell
where the unset case is silent. `set -u` (`nounset`) was never part of the
contract upstream. Patching `etc/bashrc` directly would diverge from ESI;
fix sits in our wrapper instead.

## Impact

- ESI v2512 sources cleanly under `set -eo pipefail`.
- Foundation v13 sources cleanly under the same.
- `set -u` is reintroduced **after** the OpenFOAM environment is loaded
  for the rest of our scripts.

## Status / Resolution

Worked around in our environment scripts; no upstream fix sought.

## Related

- `05_oneapi_intel_mpi_path_priority.md` — next pitfall in the same wrapper
- `03_esi_repo_login_required_tarball_fallback.md`
