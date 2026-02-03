#!/bin/env bash

# override the default scram arch
export SCRAM_ARCH=el8_amd64_gcc13

source /cvmfs/cms.cern.ch/cmsset_default.sh
CMSSW_VERSION=$(scram list CMSSW | grep -P "cmssw/CMSSW_\d{2}_\d{1,2}_X_\d{4}-\d{2}-\d{2}-\d{4}$" | awk -F'/' '{print $10}' | sort -r | head -n 1)

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
git cms-addpkg RecoTracker/LST RecoTracker/LSTCore
# Add extra packages
CLEAN_LIST=$(echo "${PACKAGES}" | tr -d '[:space:]')
IFS=',' read -ra PKGS <<< "$CLEAN_LIST"
for pkg in "${PKGS[@]}"; do
  echo "Adding extra package ${pkg}"
  git cms-addpkg $pkg
done
# Add packages that changed in the PR
PKGS=$(git diff --name-only reference_branch...pr_branch | awk -F/ 'NF>=2 {print $1"/"$2} NF<2 {print "."}' | sort -u)
for pkg in $PKGS; do
  echo "Adding changed package ${pkg}"
  git cms-addpkg $pkg
done
# Temporarily merge target branch
git config user.email "gha@example.com" && git config user.name "GHA"
git merge --no-commit --no-ff SegLink/${TARGET_BRANCH} || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)
git commit -m "Temporary merge" || echo "Nothing to commit"
# Merge required PRs
CLEAN_LIST=$(echo "${REQUIRED_PRS}" | tr -d '[:space:]')
IFS=',' read -ra PRS <<< "$CLEAN_LIST"
for pr in "${PRS[@]}"; do
  echo "Merging required PR${pr}"
  git fetch SegLink refs/pull/${pr}/head:pr-${pr}
  git merge pr-${pr} --allow-unrelated-histories -m "Merge PR${pr}"
done

# Run checks
eval `scramv1 runtime -sh`
echo "Checking format"
scram b code-format
git diff --exit-code || (echo "***\nError: There are unformatted files. Please run 'scram b code-format'.\n***" && false)
echo "Running checks"
scram b -j 4 code-checks
git diff --exit-code || (echo "***\nError: There are suggested changes. Please run 'scram b code-checks'.\n***" && false)
echo "Checking headers"
scram b -j 4 check-headers
