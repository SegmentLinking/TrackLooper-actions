#!/bin/env bash

# Builds the reference and PR branches in the same way as the standalone run.sh script and works out
# which version of RecoTracker/LSTGeometry each of them has. Runs on the host (it only needs git).

# Print all commands and exit on error
set -e -v

# Set up github config to avoid issues
git config user.email "gha@example.com" && git config user.name "GHA"

# Save current branch
git checkout -b pr_branch

# Merge reference branch into master/release in case they are different
if [[ -z "$RELEASE" || "$RELEASE" == "latest" ]]; then
  git checkout origin/master
else
  git remote add official-cmssw https://github.com/cms-sw/cmssw.git || echo "Remote already exists"
  # Keep the official remote a blobless partial clone too, since the full history is huge
  git config remote.official-cmssw.promisor true
  git config remote.official-cmssw.partialclonefilter blob:none
  git fetch official-cmssw tag $RELEASE --no-tags
  git checkout $RELEASE
fi
git switch -c reference_branch
if [[ -n "$TARGET_BRANCH" && (-z "$RELEASE" || "$RELEASE" == "latest") ]]; then
  git merge origin/$TARGET_BRANCH --allow-unrelated-histories || (echo -e "***\nError: There are conflicts between target branch and master that need to be resolved.\n***" && false)
fi
# Merge required PRs
CLEAN_LIST=$(echo "${REQUIRED_PRS}" | tr -d '[:space:]')
IFS=',' read -ra PRS <<< "$CLEAN_LIST"
for pr in "${PRS[@]}"; do
  echo "Merging required PR${pr}"
  git fetch origin refs/pull/${pr}/head:pr-${pr}
  git merge pr-${pr} --allow-unrelated-histories -m "Merge PR${pr}"
done

# Go back to PR branch and merge reference
git checkout pr_branch
if [[ -n "$TARGET_BRANCH" ]]; then
  git merge reference_branch --allow-unrelated-histories || (echo -e "***\nError: There are conflicts between target branch and PR branch that need to be resolved.\n***" && false)
fi

# The git tree hash identifies the exact contents of the package, so it is used as the cache key and
# to check whether the PR changes LSTGeometry
REF_TREE=$(git rev-parse reference_branch:RecoTracker/LSTGeometry)
PR_TREE=$(git rev-parse pr_branch:RecoTracker/LSTGeometry)
git archive -o lstgeometry_reference.tar reference_branch RecoTracker/LSTGeometry
git archive -o lstgeometry_pr.tar pr_branch RecoTracker/LSTGeometry

echo "ref-tree=$REF_TREE" >> $GITHUB_OUTPUT
echo "pr-tree=$PR_TREE" >> $GITHUB_OUTPUT
if [[ "$REF_TREE" == "$PR_TREE" ]]; then
  echo "LSTGeometry is not changed by the PR, the reference maps will be used for both branches"
  echo "changed=false" >> $GITHUB_OUTPUT
else
  echo "LSTGeometry is changed by the PR, separate maps are needed for the PR branch"
  echo "changed=true" >> $GITHUB_OUTPUT
fi
