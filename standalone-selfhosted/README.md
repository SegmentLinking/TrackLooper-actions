# TrackLooper Standalone Testing Action (self-hosted)

The action in this directory tests the standalone version of [LST](https://github.com/SegmentLinking/cmssw/tree/master/RecoTracker/LSTCore/standalone). This action builds the code from a Pull Request (PR), runs over the PU200 sample, and generates validation plots. It then builds and run the code from the master branch, and produces comparison plots between the PR and the master branch. The `action.yml` file contains the needed configuration and setup, and the `run.sh` file contains the testing script.

## Inputs

| Name | Description | Required |
| --- | --- | --- |
| `pr-number` | The PR number. | Yes |

## Outputs

| Name | Description |
| --- | --- |
| `archive-repo` | The name of the repository where the plots will be stored. It includes the owner of the repository, i.e. it is of the form `owner/repo`. |
| `archive-branch` | The branch of the repository where the plots will be stored. |
| `archive-dir` | The directory containing the data that will be stored in the archive repository. |
| `comment` | The comment that will be posted in the PR if the test passes. |

These are outputs of this action instead of being hardcoded into the CI of the main repository so that they can easily be changed without modifying the main repository.
