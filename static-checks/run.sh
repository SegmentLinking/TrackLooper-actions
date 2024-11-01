#!/bin/env bash

CMSSW_VERSION=CMSSW_14_2_0_pre3

# Print all commands and exit on error
set -e -v

# Build and run the PR
echo "Initializing CMSSW..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
scramv1 project CMSSW $CMSSW_VERSION
cd $CMSSW_VERSION/src
eval `scramv1 runtime -sh`
git cms-init --upstream-only
git remote add SegLink https://github.com/SegmentLinking/cmssw.git
git fetch SegLink refs/pull/${PR_NUMBER}/head:SegLink_cmssw
git checkout SegLink_cmssw
git fetch SegLink $TARGET_BRANCH
git cms-addpkg RecoTracker/LST RecoTracker/LSTCore Configuration/ProcessModifiers RecoTracker/ConversionSeedGenerators RecoTracker/FinalTrackSelectors RecoTracker/IterativeTracking
# Temporarily merge target branch
git config user.email "gha@example.com" && git config user.name "GHA"
git merge --no-commit --no-ff SegLink/${TARGET_BRANCH} || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)
git commit -m "Temporary merge" || echo "Nothing to commit"
eval `scramv1 runtime -sh`
echo "Checking format"
scram b code-format
git diff --exit-code || (echo "***\nError: There are unformatted files. Please run 'scram b code-format'.\n***" && false)
echo "Running checks"
scram b -j 4 code-checks
git diff --exit-code || (echo "***\nError: There are suggested changes. Please run 'scram b code-checks'.\n***" && false)
echo "Checking headers"
scram b -j 4 check-headers
