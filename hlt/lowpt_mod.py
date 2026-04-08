process.load('RecoTracker.LSTCore.lstGeometryESProducer_cfi')
process.load('RecoTracker.LST.lstModulesDevESProducer_cfi')
process.load('RecoTracker.LST.lstInputProducer_cfi')
process.load('RecoTracker.LST.lstProducer_cfi')
process.lstGeometryESProducer.ptCut = 0.6
process.lstModulesDevESProducer.ptCut = 0.6
process.lstInputProducer.ptCut = 0.6
process.lstProducer.ptCut = 0.6
