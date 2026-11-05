# TrackLooper Standalone Module Maps Action

The action in this directory generates the LST module maps (module connections, pixel maps, module orientations and centroids) with [LSTGeometry](https://github.com/SegmentLinking/cmssw/tree/master/RecoTracker/LSTGeometry) for the [standalone action](../standalone), instead of taking them from the [RecoTracker-LSTCore](https://github.com/SegmentLinking/RecoTracker-LSTCore) data repository.

It builds the reference and PR branches the same way as the standalone action (`prepare.sh`, which only needs git) and uses the git tree hash of `RecoTracker/LSTGeometry` in each branch to identify its version. The maps are cached with `actions/cache` under the key `lst-maps-<cache version>-<tree hash>-pt<pT cut>`, so they are only generated (`generate.sh`, inside `cmssw/el9:x86_64`) when that version of LSTGeometry has not been seen before. If the PR does not change LSTGeometry, the reference maps are used for both branches.

The maps are uploaded as an artifact with this layout, which is what the `maps-dir` input of the standalone action expects:

```
reference/OT800_IT615_pt<pT cut>/...
pr/OT800_IT615_pt<pT cut>/...
```

The maps also depend on the tracker geometry and conditions of the IB, which are not part of the cache key. If those change, bump `MAPS_CACHE_VERSION` in `action.yml` to regenerate all the maps.

## Inputs

| Name | Description | Required |
| --- | --- | --- |
| `pr-number` | PR number (if 0, use master) | True |
| `required-prs` | Comma-separated list of required PR numbers that must be merged before checks are run | False |
| `low-pt` | Generate the maps for the low pT setup (pT cut of 0.6 instead of 0.8) | False |
| `release` | CMSSW release to use | False |
| `artifact-name` | Name of the artifact where the maps will be uploaded | True |

## Outputs

| Name | Description |
| --- | --- |
| `changed` | Whether the PR changes LSTGeometry (and therefore has its own maps). |
