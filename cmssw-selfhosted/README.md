# TrackLooper CMSSW Testing Action

The action in this directory tests the cmssw integration of [LST](https://github.com/SegmentLinking/cmssw/tree/master/RecoTracker/LSTCore/standalone). This action builds the code from a Pull Request (PR), sets it up as an external package in CMSSW, and runs steps 3 and 4 of the 21034.1 workflow. The `action.yml` file contains the needed configuration and setup, and the `run.sh` file contains the testing script.

## Inputs

| Name | Description | Required |
| --- | --- | --- |
| `pr-number` | The PR number. | Yes |
| `cmssw-branch` | The branch of the CMSSW repository that should be used for testing. This can be used when making parallel changes in the TrackLooper and CMSSW repositories. If this input is set to `"default"`, then the default branch configured in `run.sh` will be used. | Yes |

## Outputs

| Name | Description |
| --- | --- |
| `archive-repo` | The name of the repository where the plots will be stored. It includes the owner of the repository, i.e. it is of the form `owner/repo`. |
| `archive-branch` | The branch of the repository where the plots will be stored. |
| `archive-dir` | The directory containing the data that will be stored in the archive repository. |
| `comment` | The comment that will be posted in the PR if the test passes. |

These are outputs of this action instead of being hardcoded into the CI of the main repository so that they can easily be changed without modifying the main repository.
