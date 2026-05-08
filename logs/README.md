# Build Logs

Captured outputs from the verified successful Plan I build.

| File | Content | Notes |
|---|---|---|
| [`stufe1-master.log`](stufe1-master.log) | Phase headers + Phase-8 Bericht + key markers | Full log was 25 MB (mostly ThirdParty `make` noise); trimmed to relevant lines |
| [`stufe2-master.log`](stufe2-master.log) | Header + final Phase-5/6/7 of the GO run | ex19+HYPRE pass, ex3k IGC ICE tolerated, ex2 GPU sanity converges |
| [`plan-i-iterations.md`](plan-i-iterations.md) | Chronological iteration journal — each error and fix in order | Useful when reproducing on a different system; lets you predict what will fail next |

## Sensitive content scan

Logs were inspected for credentials, tokens, hostnames; only:
- Hostname `Tavea-Station` (development workstation, no remote services)
- Username `heiko` (already public via Git author info)
- Local paths under `/opt/openfoam-v2512/`, `/opt/intel/oneapi/`, `/home/heiko/`

remain. No tokens, keys, or production-system identifiers appear.

## License

Logs include verbatim error excerpts from upstream projects (icpx, PETSc
configure, Hypre make, KokkosKernels CMake). These are reproduced as
**diagnostic citations** under fair use to document bugs and incompatibilities,
not as redistribution of upstream source. See [NOTICE.md](../NOTICE.md).
