# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Overview

This repository contains GitHub Actions and reusable workflows for the CI of [SegmentLinking/cmssw](https://github.com/SegmentLinking/cmssw), which implements the Line Segment Tracking (LST) algorithm for CMS Phase-2. The actions are kept in a separate repo so CI tweaks don't require commits to the main CMSSW repository.

The default branch for PRs in this repo is `main`.

## Repository Structure

Each top-level directory (except `Dockerfiles`) is a self-contained composite GitHub Action:

- **`checks/`** — Runs SCRAM static checks (`code-format`, `code-checks`, `check-headers`) inside a Docker container with CVMFS mounted. Uses `cmssw/el9:x86_64`.
- **`standalone/`** — Builds and runs the standalone LST code (from `RecoTracker/LSTCore/standalone`) against PU200 sample, generates efficiency/fake-rate/duplicate-rate comparison plots between the PR branch and target branch. Uses `ariostas/el9:standalone`.
- **`cmssw/`** — Builds the CMSSW integration and runs workflow 34634.712 (Phase-2 tracking reconstruction), generates DQM comparison plots. Uses `ariostas/el9:cmssw`.
- **`hlt/`** — Builds and runs the HLT workflow (Phase2 L1P2GT+HLT:75e33), generates HLT tracking comparison plots. Uses `ariostas/el9:hlt`.
- **`upload-plots/`** — Pushes a plots directory to the archive repo using an SSH deploy key (shallow, sparse clone since the archive is large; retries the push if other jobs push concurrently).
- **`.github/workflows/`** — Reusable caller workflows (`workflow_call`) that wrap the above actions and add GitHub Checks API status reporting via `LouisBrunner/checks-action`.
- **`Dockerfiles/`** — Dockerfiles to build the Docker images used by the actions. Images are based on `cmssw/el9:x86_64` pre-packaged with test data files.

## Action Architecture

Each action follows the same pattern:
1. `action.yml` — Declares inputs/outputs, mounts CVMFS (on hosted runners), pulls a Docker image, and runs `run.sh` inside the container. On `self-hosted` runners (GPU), it runs `run.sh` directly without Docker.
2. `run.sh` — The actual build and test script that runs inside the container. Sets `SCRAM_ARCH=el9_amd64_gcc14` and sources CVMFS CMSSW environment.

The reusable workflows in `.github/workflows/` wrap these actions and additionally:
- Create GitHub App tokens to post Checks API statuses (in-progress and final)
- Upload result plots to the archive repo (`<owner>/lst-performance-plots-archive-2026`) via SSH deploy key
- Post a comment on the PR with embedded plot images

## Key Behaviors in `run.sh` Scripts

**Branch strategy**: Each script constructs two git branches — `reference_branch` (target branch + required PRs merged in) and `pr_branch` (the PR head). It runs the test on both, then generates comparison plots.

**`pr-number: 0`**: Special case — uses `master` branch and skips comparison (no target branch, no PR comment).

**`required-prs`**: Comma-separated PR numbers that are merged into the reference branch before testing. Used when a PR depends on another unmerged PR.

**`low-pt`**: When `true`, injects `lowpt_mod.py` into the generated cmsDriver config to set `ptCut = 0.6` on all LST modules.

**`runs-on: self-hosted`** vs hosted: Self-hosted runners have GPUs and pre-mounted CVMFS + data files at `/data2/segmentlinking/`. Hosted runners use Docker with CVMFS mounted and use `--accelerators cpu`.

**CMSSW release selection**: Defaults to the latest nightly (`CMSSW_XX_Y_X_YYYY-MM-DD-HHMM`) by parsing `scram list CMSSW`. Can be overridden with the `release` input. Both full IBs (`cms/cmssw/`) and patch IBs (`cms/cmssw-patch/`) are matched. Patch IBs only contain the packages that changed w.r.t. their base full IB, so the standalone build sets `CMSSW_RELEASE_BASE=$CMSSW_FULL_RELEASE_BASE` to find the remaining headers (the other actions use a SCRAM developer area, which handles patch releases on its own).

## Docker Images

Built from `Dockerfiles/` directory. Each image pre-packages the necessary ROOT data files:
- `ariostas/el9:standalone` — includes `trackingNtuple_ttbar_PU200.root`
- `ariostas/el9:cmssw` — includes `step2_34634.712_100Events.root`
- `ariostas/el9:hlt` — includes `step1_hlt_100Events.root`

To rebuild and push an image after updating data files, see `Dockerfiles/README.md`.

## Dependabot

Configured to monthly update GitHub Actions pinned versions in `.github/workflows/`, `standalone/`, `cmssw/`, `hlt/`, and `checks/` directories (grouped as `actions`).
