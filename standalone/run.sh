#!/bin/env bash

source /cvmfs/cms.cern.ch/cmsset_default.sh
export FORCED_CMSSW_VERSION=$(scram list CMSSW | grep -P " CMSSW_\d{2}_\d{1,2}_X_\d{4}-\d{2}-\d{2}-\d{4} " | awk '{print $2}' | sort -r | head -n 1)

# Print all commands and exit on error
set -e -v

# Temporarily merge the target branch
git checkout -b pr_branch
git fetch --unshallow || echo "" # It might be worth switching actions/checkout to use depth 0 later on
git config user.email "gha@example.com" && git config user.name "GHA" # For some reason this is needed even though nothing is being committed
git merge --no-commit --no-ff origin/${TARGET_BRANCH} || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)

# Download data files
cd RecoTracker/LSTCore
git clone --branch add_t33_maps https://github.com/SegmentLinking/RecoTracker-LSTCore.git data

# Build and run the PR. Create validation plots
cd standalone
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
sdl_make_tracklooper -mcAs || lst_make_tracklooper -mcAs
LOW_PT_FLAG=$([[ $LOW_PT == "true" ]] && echo "--ptCut 0.6" || echo "")
echo "Running LST..."
(which sdl_cpu && (sdl_cpu -i PU200 -o LSTNtuple_after.root -s 4 -v 1 $LOW_PT_FLAG | tee -a /home/TrackLooper/timing_PR.txt)) || echo "sdl_cpu not found"
(which lst_cpu && (lst_cpu -i PU200 -o LSTNtuple_after.root -s 4 -v 1 $LOW_PT_FLAG | tee -a /home/TrackLooper/timing_PR.txt)) || echo "lst_cpu not found"
createPerfNumDenHists -i LSTNtuple_after.root -o LSTNumDen_after.root
echo "Creating validation plots..."
python3 efficiency/python/lst_plot_performance.py LSTNumDen_after.root -t "validation_plots"

# Checkout the target branch so we can compare what has changed
git stash
PRSHA=$(git rev-parse HEAD)
git checkout origin/${TARGET_BRANCH}

# Build and run target. Create comparison plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
# Only CPU version is compiled since the target branch has already been tested
sdl_make_tracklooper -mcCs || lst_make_tracklooper -mcCs
echo "Running LST..."
(which sdl_cpu && (sdl_cpu -i PU200 -o LSTNtuple_before.root -s 4 -v 1 $LOW_PT_FLAG | tee -a /home/TrackLooper/timing_target.txt)) || echo "sdl_cpu not found"
(which lst_cpu && (lst_cpu -i PU200 -o LSTNtuple_before.root -s 4 -v 1 $LOW_PT_FLAG | tee -a /home/TrackLooper/timing_target.txt)) || echo "lst_cpu not found"
createPerfNumDenHists -i LSTNtuple_before.root -o LSTNumDen_before.root
# Go back to the PR commit so that the git tag is consistent everywhere
git checkout $PRSHA
echo "Creating comparison plots..."
python3 efficiency/python/lst_plot_performance.py --compare LSTNumDen_after.root LSTNumDen_before.root --comp_labels this_PR,target_branch -t "comparison_plots"

# Copy a few plots that will be attached in the PR comment
mkdir /home/TrackLooper/$ARCHIVE_DIR
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_ptzoom.png        /home/TrackLooper/$ARCHIVE_DIR/eff_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_etacoarsezoom.png /home/TrackLooper/$ARCHIVE_DIR/eff_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_ptzoom.png            /home/TrackLooper/$ARCHIVE_DIR/fake_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_etacoarsezoom.png     /home/TrackLooper/$ARCHIVE_DIR/fake_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_ptzoom.png            /home/TrackLooper/$ARCHIVE_DIR/dup_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_etacoarsezoom.png     /home/TrackLooper/$ARCHIVE_DIR/dup_eta_comp.png

# Delete some of the data to make the archive smaller
cd performance
find . -type f -name "*.png" -delete
find . -type f -name "*_11_0_*" -delete
find . -type f -name "*_13_0_*" -delete
find . -type f -name "*_211_0_*" -delete
find . -type f -name "*_321_0_*" -delete
cd ..
tar zcf /home/TrackLooper/$ARCHIVE_DIR/plots.tar.gz performance
