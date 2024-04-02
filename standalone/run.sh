#!/bin/env bash

# Print all commands and exit on error
set -e -v

# Temporarily merge the master branch
git checkout -b pr_branch
git fetch --unshallow || echo "" # It might be worth switching actions/checkout to use depth 0 later on
git config user.email "gha@example.com" && git config user.name "GHA" # For some reason this is needed even though nothing is being committed
git merge --no-commit --no-ff origin/master || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)

# Build and run the PR. Create validation plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
sdl_make_tracklooper -mc || echo "Done"
if [[ ! -f bin/sdl_cpu || ! -f bin/sdl_cuda ]]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
echo "Running LST..."
sdl_cpu -i PU200 -o LSTNtuple_after.root -s 4
createPerfNumDenHists -i LSTNtuple_after.root -o LSTNumDen_after.root
echo "Creating validation plots..."
python3 efficiency/python/lst_plot_performance.py LSTNumDen_after.root -t "validation_plots"

# Checkout the master branch so we can compare what has changed
git stash
PRSHA=$(git rev-parse HEAD)
git checkout origin/master

# Build and run master. Create comparison plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
# Only CPU version is compiled since the master branch has already been tested
sdl_make_tracklooper -mcC || echo "Done"
if [[ ! -f bin/sdl_cpu ]]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
echo "Running LST..."
sdl_cpu -i PU200 -o LSTNtuple_before.root -s 4
createPerfNumDenHists -i LSTNtuple_before.root -o LSTNumDen_before.root
# Go back to the PR commit so that the git tag is consistent everywhere
git checkout $PRSHA
echo "Creating comparison plots..."
python3 efficiency/python/lst_plot_performance.py --compare LSTNumDen_after.root LSTNumDen_before.root --comp_labels This_PR,master -t "comparison_plots"

# Copy a few plots that will be attached in the PR comment
mkdir $ARCHIVE_DIR
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_ptzoom.png        $ARCHIVE_DIR/eff_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_base_0_0_eff_etacoarsezoom.png $ARCHIVE_DIR/eff_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_ptzoom.png            $ARCHIVE_DIR/fake_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_fakerate_etacoarsezoom.png     $ARCHIVE_DIR/fake_eta_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_ptzoom.png            $ARCHIVE_DIR/dup_pt_comp.png
cp performance/comparison_plots*/mtv/var/TC_duplrate_etacoarsezoom.png     $ARCHIVE_DIR/dup_eta_comp.png

# Delete some of the data to make the archive smaller
cd performance
find . -type f -name "*.png" -delete
find . -type f -name "*_11_0_*" -delete
find . -type f -name "*_13_0_*" -delete
find . -type f -name "*_211_0_*" -delete
find . -type f -name "*_321_0_*" -delete
cd ..
tar zcf $ARCHIVE_DIR/plots.tar.gz performance
