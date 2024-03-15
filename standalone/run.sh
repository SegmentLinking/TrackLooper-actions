#!/bin/env bash

# Print all commands and exit on error
set -e -v

# Build and run the PR. Create validation plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
make code/rooutil/
sdl_make_tracklooper -c || echo "Done"
if ! [ -f bin/sdl ]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
echo "Running LST..."
rm SDL/libsdl_cuda.so
sdl -i PU200 -o LSTNtuple_after.root -s 4
createPerfNumDenHists -i LSTNtuple_after.root -o LSTNumDen_after.root
echo "Creating validation plots..."
python3 efficiency/python/lst_plot_performance.py LSTNumDen_after.root -t "validation_plots"

# Checkout the master branch so we can compare what has changed
PRSHA=$(git rev-parse HEAD)
git fetch origin master
git checkout origin/master

# Build and run master. Create comparison plots
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
make clean || echo "make clean failed"
make code/rooutil/
sdl_make_tracklooper -cC || echo "Done"
if ! [ -f bin/sdl ]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
echo "Running LST..."
sdl -i PU200 -o LSTNtuple_before.root -s 4
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
