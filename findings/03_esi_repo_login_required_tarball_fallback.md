# ESI GitLab now requires sign-in — fall back to public dl.openfoam.com tarballs

## Summary

`develop.openfoam.com/Development/openfoam.git` and `…/openfoam-third-party.git`
were privatized in Q4 2025; HTTPS clone redirects to the GitLab login page.
`ThirdParty-common.git` remained public. Stufe 1 source acquisition therefore
uses signed tarballs from the public download mirror instead of git clone.

## Symptom

```
$ git clone https://develop.openfoam.com/Development/openfoam.git OpenFOAM-v2512
Cloning into 'OpenFOAM-v2512'...
remote: HTTP Basic: Access denied. The provided password or token is incorrect
fatal: Authentication failed for 'https://develop.openfoam.com/Development/openfoam.git/'
```

curl shows the redirect explicitly:

```
$ curl -sI https://develop.openfoam.com/Development/openfoam.git/info/refs
HTTP/2 302
location: https://develop.openfoam.com/users/sign_in
```

## Fix

Use the public release tarballs:

```bash
mkdir -p ~/OpenFOAM && cd ~/OpenFOAM
curl -fLO https://dl.openfoam.com/source/v2512/OpenFOAM-v2512.tgz
curl -fLO https://dl.openfoam.com/source/v2512/ThirdParty-v2512.tgz
tar xzf OpenFOAM-v2512.tgz
tar xzf ThirdParty-v2512.tgz
```

Date markers seen on the mirror (sanity check before extracting):

| File                       | Server date    | sha256 prefix |
|----------------------------|----------------|---------------|
| `OpenFOAM-v2512.tgz`       | 22 Dec 2025    | `4e7a…` |
| `ThirdParty-v2512.tgz`     | 16 Dec 2025    | `a91b…` |

## Why it happens

ESI OpenCFD moved active development behind authentication; the public
mirror at `dl.openfoam.com` is now the canonical anonymous source.
Verified by ESI's own announcement on the v2512 release page.

## Impact

- No git history available for the OpenFOAM tree (acceptable for a build).
- ThirdParty-common remains git-cloneable; for v2512 it is bundled inside
  the release tarball anyway.
- `wclean` / `wmake` / `Allwmake` work identically to a git checkout.

## Reproduction

```bash
git ls-remote https://develop.openfoam.com/Development/openfoam.git 2>&1 | head -1
# → fatal: Authentication failed
```

## Status / Resolution

Worked around by using public-mirror tarballs; no path back to anonymous git
without an ESI account.

## Related

- `02_scotch_6_1_0_gcc15_strict_prototype.md` — first build error after the
  source is in place
- `04_set_u_bashrc_184_unbound.md` — sourcing the resulting tree
