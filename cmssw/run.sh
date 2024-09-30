#!/bin/env bash

CMSSW_VERSION=CMSSW_14_2_0_pre1

# Print all commands and exit on error
set -e -v

# Build and run the PR
echo "Initializing CMSSW..."
source /cvmfs/cms.cern.ch/cmsset_default.sh
scramv1 project CMSSW $CMSSW_VERSION
cd $CMSSW_VERSION/src
eval `scramv1 runtime -sh`
# cms-init is too slow
# git cms-init --upstream-only
git init
git remote add SegLink https://github.com/SegmentLinking/cmssw.git
git sparse-checkout set .gitignore .clang-format .clangtidy
git fetch SegLink refs/pull/${PR_NUMBER}/head:SegLink_cmssw
git checkout SegLink_cmssw
git fetch SegLink $TARGET_BRANCH
git cms-addpkg RecoTracker/LST RecoTracker/LSTCore \
  Configuration/ProcessModifiers Configuration/PyReleaseValidation \
  RecoTracker/ConversionSeedGenerators RecoTracker/FinalTrackSelectors RecoTracker/IterativeTracking \
  HeterogeneousCore/AlpakaInterface
# Temporarily merge target branch
git config user.email "gha@example.com" && git config user.name "GHA"
git merge --no-commit --no-ff SegLink/${TARGET_BRANCH} || (echo "***\nError: There are merge conflicts that need to be resolved.\n***" && false)
eval `scramv1 runtime -sh`
echo "Building CMSSW..."
scram b -j 4
# Download data files
git clone --branch add_t33_maps https://github.com/SegmentLinking/RecoTracker-LSTCore.git RecoTracker/LSTCore/data
echo "Starting LST test..."
cmsDriver.py step3 \
  -s RAW2DIGI,RECO:reconstruction_trackingOnly,VALIDATION:@trackingOnlyValidation,DQM:@trackingOnlyDQM \
  --conditions auto:phase2_realistic_T33 \
  --datatier GEN-SIM-RECO,DQMIO \
  -n 100 \
  --eventcontent RECOSIM,DQM \
  --geometry Extended2026D110 \
  --era Phase2C17I13M9 \
  --procModifiers trackingIters01,trackingLST \
  --accelerators cpu \
  --nThreads 4 \
  --filein file:/data2/segmentlinking/step2_29834.1_100Events.root \
  --fileout file:step3_out.root \
  --no_exec
if [[ "$LOW_PT" == "true" ]]; then
  sed -i "30i process.load('RecoTracker.LST.lstModulesDevESProducer_cfi')\nprocess.load('RecoTracker.LST.lstProducer_cfi')\nprocess.lstModulesDevESProducer.ptCutLabel = '0.6'\nprocess.lstProducer.ptCutLabel = '0.6'\nprocess.lstProducer.ptCut = 0.6" step3_RAW2DIGI_RECO_VALIDATION_DQM.py
fi
echo "Setting up siteconf..."
git clone https://github.com/cms-sw/siteconf.git
sed -i '/<prefer ipfamily="0"\/>/,/<backupproxy url="http:\/\/cmsbproxy\.fnal\.gov:3128"\/>/d' siteconf/local/JobConfig/site-local-config.xml
export SITECONFIG_PATH=$PWD/siteconf/local
echo "Running 29834.1 (+LST) workflow..."
cmsRun step3_RAW2DIGI_RECO_VALIDATION_DQM.py
cmsDriver.py step4 \
  -s HARVESTING:@trackingOnlyValidation+@trackingOnlyDQM \
  --conditions auto:phase2_realistic_T33 \
  --mc \
  --geometry Extended2026D110 \
  --scenario pp \
  --filetype DQM \
  --era Phase2C17I13M9 \
  -n 100 \
  --filein file:step3_out_inDQM.root \
  --fileout file:step4_out.root \
  --no_exec
cmsRun step4_HARVESTING.py
mv DQM_V0001_R000000001__Global__CMSSW_X_Y_Z__RECO.root this_PR.root
rm step3_*.root

# Checkout the target branch so we can compare what has changed
git stash
PRSHA=$(git rev-parse HEAD)
git checkout SegLink/${TARGET_BRANCH}

# Build and run target
eval `scramv1 runtime -sh`
# Recompile CMSSW in case anything changed in the headers
scram b clean
scram b -j 4
echo "Running 29834.1 (+LST) workflow..."
cmsRun step3_RAW2DIGI_RECO_VALIDATION_DQM.py
cmsRun step4_HARVESTING.py
mv DQM_V0001_R000000001__Global__CMSSW_X_Y_Z__RECO.root target_branch.root
# Go back to the PR commit so that the git tag is consistent everywhere
git checkout $PRSHA

# Create comparison plots
makeTrackValidationPlots.py --extended -o plots_pdf target_branch.root this_PR.root
makeTrackValidationPlots.py --extended --png -o plots_png target_branch.root this_PR.root

# Copy a few plots that will be attached in the PR comment
mkdir /home/TrackLooper/$ARCHIVE_DIR
cp plots_png/plots_ootb/effandfakePtEtaPhi.png /home/TrackLooper/$ARCHIVE_DIR

mkdir plots
cp -r plots_pdf/plots_ootb plots
cp -r plots_pdf/plots_highPurity plots
cp -r plots_pdf/plots_building_highPtTripletStep plots
rm -r plots/plots_ootb/*/ plots/plots_highPurity/*/ plots/plots_building_highPtTripletStep/*/
tar zcf /home/TrackLooper/$ARCHIVE_DIR/plots.tar.gz plots
