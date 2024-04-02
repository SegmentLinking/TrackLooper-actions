#!/bin/env bash

if [ -n "$CMSSW_BRANCH" ]; then
  # Remove \r and other control characters that could be in there (newline characters in github are \r\n)
  CMSSW_BRANCH=$(echo $CMSSW_BRANCH | tr -d '[:cntrl:]')
  # If the branch is an integer, interpret it as a PR number
  if [[ "$CMSSW_BRANCH" =~ ^[0-9]+$ ]]; then
    CMSSW_BRANCH="refs/pull/${CMSSW_BRANCH}/head"
  fi
  # Validate the cmssw branch name to avoid code injection
  CMSSW_BRANCH=$(git check-ref-format --branch $CMSSW_BRANCH || echo "default")
fi
# Set the CMSSW branch to use
# When using a non-default branch comparison plots are not made because the changes in both repos presumably depend on each other
COMPARE_TO_MASTER=false
if [ -z "$CMSSW_BRANCH" ] || [ "$CMSSW_BRANCH" == "default" ]; then
  CMSSW_BRANCH=CMSSW_14_1_0_pre0_LST_X
  COMPARE_TO_MASTER=true
fi

# Print all commands and exit on error
set -e -v

# Temporarily merge the master branch
git checkout -b pr_branch
git fetch --unshallow || echo "" # It might be worth switching actions/checkout to use depth 0 later on
git config user.email "gha@example.com" && git config user.name "GHA" # For some reason this is needed even though nothing is being committed
git merge --no-commit --no-ff origin/master || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)

# Build and run the PR
echo "Running setup script..."
source setup.sh
echo "Building and LST..."
sdl_make_tracklooper -mc || echo "Done"
if [[ ! -f bin/sdl_cpu || ! -f bin/sdl_cuda ]]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
echo "Setting up CMSSW..."
scramv1 project CMSSW $CMSSW_VERSION
cd $CMSSW_VERSION/src
eval `scramv1 runtime -sh`
git cms-init --upstream-only
git remote add SegLink https://github.com/SegmentLinking/cmssw.git
git fetch SegLink ${CMSSW_BRANCH}:SegLink_cmssw
git checkout SegLink_cmssw
git cms-addpkg RecoTracker/LST Configuration/ProcessModifiers RecoTracker/ConversionSeedGenerators RecoTracker/FinalTrackSelectors RecoTracker/IterativeTracking
cat <<EOF >lst_headers.xml
<tool name="lst_headers" version="1.0">
  <client>
    <environment name="LSTBASE" default="$PWD/../../../TrackLooper"/>
    <environment name="INCLUDE" default="\$LSTBASE"/>
  </client>
  <runtime name="LST_BASE" value="\$LSTBASE"/>
</tool>
EOF
cat <<EOF >lst_cpu.xml
<tool name="lst_cpu" version="1.0">
  <client>
    <environment name="LSTBASE" default="$PWD/../../../TrackLooper"/>
    <environment name="LIBDIR" default="\$LSTBASE/SDL"/>
    <environment name="INCLUDE" default="\$LSTBASE"/>
  </client>
  <runtime name="LST_BASE" value="\$LSTBASE"/>
  <lib name="sdl_cpu"/>
</tool>
EOF
scram setup lst_headers.xml
scram setup lst_cpu.xml
eval `scramv1 runtime -sh`
# We need to remove the Cuda plugin because it fails to compile if there is no GPU
sed -i '/<library file="alpaka\/\*\.cc" name="RecoTrackerLSTPluginsPortableCuda">/,/<\/library>/d' RecoTracker/LST/plugins/BuildFile.xml
echo "Building CMSSW..."
scram b -j 4
echo "Starting LST test..."
cmsDriver.py step3 -s RAW2DIGI,RECO:reconstruction_trackingOnly,VALIDATION:@trackingOnlyValidation,DQM:@trackingOnlyDQM --conditions auto:phase2_realistic_T21 --datatier GEN-SIM-RECO,DQMIO -n 100 --eventcontent RECOSIM,DQM --geometry Extended2026D88 --era Phase2C17I13M9 --procModifiers trackingLST,trackingIters01 --nThreads 4 --no_exec
sed -i "28i process.load('Configuration.StandardSequences.Accelerators_cff')\nprocess.load('HeterogeneousCore.AlpakaCore.ProcessAcceleratorAlpaka_cfi')" step3_RAW2DIGI_RECO_VALIDATION_DQM.py
sed -i "s|fileNames = cms.untracked.vstring('file:step3_DIGI2RAW.root')|fileNames = cms.untracked.vstring('file:/data2/segmentlinking/step2_21034.1_100Events.root')|" step3_RAW2DIGI_RECO_VALIDATION_DQM.py
echo "Setting up siteconf..."
git clone https://github.com/cms-sw/siteconf.git
sed -i '/<prefer ipfamily="0"\/>/,/<backupproxy url="http:\/\/cmsbproxy\.fnal\.gov:3128"\/>/d' siteconf/local/JobConfig/site-local-config.xml
export SITECONFIG_PATH=$PWD/siteconf/local
echo "Running 21034.1 workflow..."
cmsRun step3_RAW2DIGI_RECO_VALIDATION_DQM.py
cmsDriver.py step4 -s HARVESTING:@trackingOnlyValidation+@trackingOnlyDQM --conditions auto:phase2_realistic_T21 --mc  --geometry Extended2026D88 --scenario pp --filetype DQM --era Phase2C17I13M9 -n 100 --no_exec
sed -i "s|fileNames = cms.untracked.vstring('file:step4_RECO.root')|fileNames = cms.untracked.vstring('file:step3_RAW2DIGI_RECO_VALIDATION_DQM_inDQM.root')|" step4_HARVESTING.py
cmsRun step4_HARVESTING.py
mv DQM_V0001_R000000001__Global__CMSSW_X_Y_Z__RECO.root This_PR.root
rm step3_*.root

if [ "$COMPARE_TO_MASTER" == "true" ]; then
  # Checkout the master branch so we can compare what has changed
  cd ../..
  git stash
  PRSHA=$(git rev-parse HEAD)
  git checkout origin/master

  # Build and run master
  echo "Running setup script..."
  source setup.sh
  echo "Building and LST..."
  sdl_make_tracklooper -mcC || echo "Done"
  if [[ ! -f bin/sdl_cpu ]]; then echo "Build failed. Printing log..."; cat .make.log*; false; fi
  cd $CMSSW_VERSION/src
  eval `scramv1 runtime -sh`
  # Recompile CMSSW in case anything changed in the headers
  scram b clean
  scram b -j 4
  echo "Running 21034.1 workflow..."
  cmsRun step3_RAW2DIGI_RECO_VALIDATION_DQM.py
  cmsRun step4_HARVESTING.py
  mv DQM_V0001_R000000001__Global__CMSSW_X_Y_Z__RECO.root master.root
  # Go back to the PR commit so that the git tag is consistent everywhere
  cd ../..
  git checkout $PRSHA
  cd $CMSSW_VERSION/src

  # Create comparison plots
  makeTrackValidationPlots.py --extended -o plots_pdf master.root This_PR.root
  makeTrackValidationPlots.py --extended --png -o plots_png master.root This_PR.root
else
  # Create validation plots
  makeTrackValidationPlots.py --extended -o plots_pdf This_PR.root
  makeTrackValidationPlots.py --extended --png -o plots_png This_PR.root
fi

# Copy a few plots that will be attached in the PR comment
mkdir $TRACKLOOPERDIR/$ARCHIVE_DIR
cp plots_png/plots_ootb/effandfakePtEtaPhi.png $TRACKLOOPERDIR/$ARCHIVE_DIR

mkdir plots
cp -r plots_pdf/plots_ootb plots
cp -r plots_pdf/plots_highPurity plots
cp -r plots_pdf/plots_building_highPtTripletStep plots
rm -r plots/plots_ootb/*/ plots/plots_highPurity/*/ plots/plots_building_highPtTripletStep/*/
tar zcf $TRACKLOOPERDIR/$ARCHIVE_DIR/plots.tar.gz plots
