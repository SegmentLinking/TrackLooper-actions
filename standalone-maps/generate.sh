#!/bin/env bash

# Builds RecoTracker/LSTGeometry from $TARBALL on top of an IB and dumps the module maps into
# $OUTPUT_DIR/OT800_IT615_pt$PT_CUT. Runs inside the container. The developer area is kept in the
# workspace, so a second call (for the PR branch) only needs to rebuild the package.

# override the default scram arch
export SCRAM_ARCH=el9_amd64_gcc14

source /cvmfs/cms.cern.ch/cmsset_default.sh
if [[ -z "$RELEASE" || "$RELEASE" == "latest" ]]; then
  CMSSW_VERSION=$(scram list CMSSW | grep -P "cmssw(-patch)?/CMSSW_\d{2}_\d{1,2}_X_\d{4}-\d{2}-\d{2}-\d{4}$" | awk -F'/' '{print $10}' | sort -rV | head -n 1)
else
  CMSSW_VERSION=$RELEASE
fi

# Print all commands and exit on error
set -e -v

WORKDIR=$PWD
if [[ ! -d $CMSSW_VERSION ]]; then
  scramv1 project CMSSW $CMSSW_VERSION
fi
cd $CMSSW_VERSION/src
eval `scramv1 runtime -sh`
rm -rf RecoTracker/LSTGeometry
tar -xf $WORKDIR/$TARBALL
scram b -j 4

cd $WORKDIR
MAPS_SUBDIR=$OUTPUT_DIR/OT800_IT615_pt$PT_CUT
rm -rf $OUTPUT_DIR
mkdir -p $MAPS_SUBDIR
cmsRun $CMSSW_BASE/src/RecoTracker/LSTGeometry/test/dumpLSTGeometry.py \
  --outputDirectory $MAPS_SUBDIR --ptCut $PT_CUT --binaryOutput

# Make sure that the files that LSTCore loads were produced
for f in endcap_orientation tilted_barrel_orientation module_connection_tracing_merged; do
  test -s $MAPS_SUBDIR/$f.bin
done
ls -lR $OUTPUT_DIR
