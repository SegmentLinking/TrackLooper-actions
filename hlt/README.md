# TrackLooper HLT Testing Action

The action in this directory tests the HLT integration of [LST](https://github.com/SegmentLinking/cmssw/tree/master/RecoTracker/LSTCore/standalone). This action builds the code from a Pull Request (PR), and runs the HLT workflow. The `action.yml` file contains the needed configuration and setup, and the `run.sh` file contains the testing script.

## Inputs

| Name | Description | Required |
| --- | --- | --- |
| `pr-number` | PR number (if 0, use master and skip comparisons) | True |
| `required-prs` | Comma-separated list of required PR numbers that must be merged before checks are run | False |
| `runs-on` | Runner where to run the workflow | False |
| `low-pt` | Run the low pT setup | False |
| `release` | CMSSW release to use | False |
| `packages` | Comma-separated list of extra packages to add | False |
| `procmodifiers` | Comma-separated list of process modifiers | False |

## Outputs

| Name | Description |
| --- | --- |
| `archive-repo` | The name of the repository where the plots will be stored. It includes the owner of the repository, i.e. it is of the form `owner/repo`. |
| `archive-branch` | The branch of the repository where the plots will be stored. |
| `archive-dir` | The directory containing the data that will be stored in the archive repository. |
| `comment` | The comment that will be posted in the PR if the test passes. |

These are outputs of this action instead of being hardcoded into the CI of the main repository so that they can easily be changed without modifying the main repository.
