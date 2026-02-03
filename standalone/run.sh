#!/bin/env bash

# override the default scram arch
export SCRAM_ARCH=el8_amd64_gcc13

source /cvmfs/cms.cern.ch/cmsset_default.sh
if [[ -z "$RELEASE" || "$RELEASE" == "latest" ]]; then
  export FORCED_CMSSW_VERSION=$(scram list CMSSW | grep -P "cmssw/CMSSW_\d{2}_\d{1,2}_X_\d{4}-\d{2}-\d{2}-\d{4}$" | awk -F'/' '{print $10}' | sort -r | head -n 1)
else
  export FORCED_CMSSW_VERSION=$RELEASE
fi

# Print all commands and exit on error
set -e -v

# Set up github config to avoid issues
git config user.email "gha@example.com" && git config user.name "GHA"

# Save current branch
git checkout -b pr_branch
git fetch --unshallow || echo "" # It might be worth switching actions/checkout to use depth 0 later on

# Merge reference branch into master/release in case they are different
if [[ -z "$RELEASE" || "$RELEASE" == "latest" ]]; then
  git checkout origin/master
else
  git remote add official-cmssw https://github.com/cms-sw/cmssw.git || echo "Remote already exists"
  git fetch official-cmssw
  git checkout $RELEASE
fi
git switch -c reference_branch
if [[ -n "$TARGET_BRANCH" && (-z "$RELEASE" || "$RELEASE" == "latest") ]]; then
  git merge origin/$TARGET_BRANCH --allow-unrelated-histories || (echo "***\nError: There are conflicts between target branch and master that need to be resolved.\n***" && false)
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
  git merge reference_branch --allow-unrelated-histories || (echo "***\nError: There are conflicts between target branch and PR branch that need to be resolved.\n***" && false)
fi

# Add extra packages
CLEAN_LIST=$(echo "${PACKAGES}" | tr -d '[:space:]')
IFS=',' read -ra PKGS <<< "$CLEAN_LIST"
for pkg in "${PKGS[@]}"; do
  echo "Adding extra package ${pkg}"
  git sparse-checkout add $pkg
done
# Add packages that changed in the PR
PKGS=$(git diff --name-only reference_branch...pr_branch | awk -F/ 'NF>=2 {print $1"/"$2} NF<2 {print "."}' | sort -u)
for pkg in $PKGS; do
  echo "Adding changed package ${pkg}"
  git sparse-checkout add $pkg
done

# Download data files
cd RecoTracker/LSTCore
git clone --branch add_t33_maps https://github.com/SegmentLinking/RecoTracker-LSTCore.git data

# Build and run the PR. Create validation plots
cd standalone
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
export MAXMAKETHREADS=$([[ $RUNS_ON == "self-hosted" ]] && echo "16" || echo "4")
LOW_PT_FLAG=$([[ $LOW_PT == "true" ]] && echo "--ptCut 0.6" || echo "")
LST_BIN=$([[ $RUNS_ON == "self-hosted" ]] && echo "lst_cuda" || echo "lst_cpu")
N_STREAMS=$([[ $RUNS_ON == "self-hosted" ]] && echo "1" || echo "4")
lst_make_tracklooper -mAs
echo "Running LST..."
$LST_BIN -i PU200 -o LSTNtuple_after.root -s $N_STREAMS -v 1 $LOW_PT_FLAG | tee -a ../../../timing_PR.txt
# Exit early if we're just testing master
if [[ -z "$TARGET_BRANCH" ]]; then
  exit 0
fi
createPerfNumDenHists -i LSTNtuple_after.root -o LSTNumDen_after.root
echo "Creating validation plots..."
python3 efficiency/python/lst_plot_performance.py LSTNumDen_after.root -t "validation_plots"
if [[ $RUNS_ON == "self-hosted" ]]; then
  echo "Running timing test"
  lst_timing PU200 | tee -a ../../../timing_PR.txt
fi

# Checkout the target branch so we can compare what has changed
git stash
PRSHA=$(git rev-parse HEAD)
git checkout reference_branch
# Merge required PRs
CLEAN_LIST=$(echo "${REQUIRED_PRS}" | tr -d '[:space:]')
IFS=',' read -ra PRS <<< "$CLEAN_LIST"
for pr in "${PRS[@]}"; do
  echo "Merging required PR${pr}"
  git fetch SegLink refs/pull/${pr}/head:pr-${pr}
  git merge pr-${pr} --allow-unrelated-histories -m "Merge PR${pr}"
done

# Build and run target. Create comparison plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
# Only CPU version is compiled since the target branch has already been tested
lst_make_tracklooper $([[ $RUNS_ON == "self-hosted" ]] && echo "-mAs" || echo "-mCs")
echo "Running LST..."
$LST_BIN -i PU200 -o LSTNtuple_before.root -s $N_STREAMS -v 1 $LOW_PT_FLAG | tee -a ../../../timing_target.txt
createPerfNumDenHists -i LSTNtuple_before.root -o LSTNumDen_before.root
# Go back to the PR commit so that the git tag is consistent everywhere
git checkout $PRSHA
echo "Creating comparison plots..."
python3 efficiency/python/lst_plot_performance.py --compare LSTNumDen_after.root LSTNumDen_before.root --comp_labels this_PR,target_branch -t "comparison_plots"
if [[ $RUNS_ON == "self-hosted" ]]; then
  echo "Running timing test"
  lst_timing PU200 | tee -a ../../../timing_target.txt
fi

# Copy a few plots that will be attached in the PR comment
mkdir ../../../$ARCHIVE_DIR
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_ptzoom.png        ../../../$ARCHIVE_DIR/eff_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_etacoarsezoom.png ../../../$ARCHIVE_DIR/eff_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_ptzoom.png            ../../../$ARCHIVE_DIR/fake_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_etacoarsezoom.png     ../../../$ARCHIVE_DIR/fake_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_ptzoom.png            ../../../$ARCHIVE_DIR/dup_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_etacoarsezoom.png     ../../../$ARCHIVE_DIR/dup_eta_comp.png

# Delete some of the data to make the archive smaller
cd performance
find . -type f -name "*.png" -delete
find . -type f -name "*_11_0_*" -delete
find . -type f -name "*_13_0_*" -delete
find . -type f -name "*_211_0_*" -delete
find . -type f -name "*_321_0_*" -delete
cd ..
tar zcf ../../../$ARCHIVE_DIR/plots.tar.gz performance
