# Bundled VRM Models

Downloaded and verified on 2026-07-12.

Every model below is a self-contained VRM 0.x file whose embedded metadata says
`licenseName=CC0`, `allowedUserName=Everyone`, and
`commercialUssageName=Allow`. The collection registry also marks the source
collections as CC0:

- https://github.com/PolygonalMind/100Avatars/releases/tag/v24.02.1
- https://raw.githubusercontent.com/ToxSam/open-source-avatars/main/data/projects.json
- https://creativecommons.org/publicdomain/zero/1.0/

## Included files

| File | Model | Creator | Source | SHA-256 |
| --- | --- | --- | --- | --- |
| `chubby_tubby_cat.vrm` | Chubby Tubby Cat | ToxSam | https://gateway.pinata.cloud/ipfs/QmY4NQRArQaEWPgyzyTuCSvyAnBUhtsshFKPjJHbbzVKLL/ChubbyTubbyCat.vrm | `f1e31eb45d28620862759e6803c42c46c61e32fdab47fcb5230ddbbb273add52` |
| `dogo_burger.vrm` | Dogo Burger | Polygonal Mind | https://arweave.net/qKrAwFf60cT1348kvQc7S5Nzn3fO0aNvJ8ybMx5Lu04 | `8b352a932c990f3a9d7b57df3d801fd0744fda0fe2798c68e5bfaec027b71673` |
| `cute_saurus.vrm` | Cute Saurus | Polygonal Mind | https://arweave.net/1-EJ5GXIlQ1ohw6GMsMnEzyK7IHhI8YDPYsjMvo_xhQ | `a5a48a0660ac7d879a4589a88ab6a50a623c712db648fa0d5fe66dfe5bbd5dbb` |
| `weird_cat.vrm` | Weird Cat | Polygonal Mind | https://arweave.net/pPaWwgWt8Gu7hJyHo_wG45lxPVV8ka8zBJJKSQD8Ngs | `8ab0d32531ca53e6dfe6be58e16f5d7aff1173a65adf447c8b4aa92f8d250495` |
| `cute_moth.vrm` | Cute Moth | Polygonal Mind | https://arweave.net/LWj4C9ClGs0ChP7oHDEEWPbGTo0HAWNMjhIRlyMkRHg | `81cfbb98d4214b930db7b4916c854c5d31f952b18ce2887118c3ddcdc5fe930d` |
| `dino_kid.vrm` | DinoKid | Polygonal Mind | https://raw.githubusercontent.com/PolygonalMind/100Avatars/master/100Avatars_045/100Avatars_045_DinoKid.vrm | `ec7770601b1e060e5710e5e7bfb3c597d395fffc90e3c60ef32fcd60f85afc48` |
| `megan_the_fox.vrm` | Megan The Fox | Polygonal Mind | https://arweave.net/up4WzT0YJfXv9woGseCIQnBSq3eH8KWASJJbNtuvEWY | `7167d50eb9fae3d3e0453ab6ab2e26b777452b5e0dc41108dfa162a3a061efd2` |

## Distribution guardrails

- Do not add a model only because an external index labels it CC0. Check the
  license embedded in the VRM file too.
- `paws_chestnut`, `merry_yulelog`, and `thumper_cranberry` are intentionally
  not bundled: their embedded metadata says `Redistribution_Prohibited`, even
  though an external collection entry currently labels them CC0.
- A developer-local `default_avatar.vrm` is ignored by Git and explicitly
  excluded from the Xcode resource phase because its redistribution provenance
  is not documented here.
