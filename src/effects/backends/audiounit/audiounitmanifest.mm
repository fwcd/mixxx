#import <AudioToolbox/AudioToolbox.h>
#include "effects/backends/effectmanifestparameter.h"

#include <memory>

#include "effects/backends/audiounit/audiounitmanager.h"
#include "effects/backends/audiounit/audiounitmanifest.h"
#include "effects/defs.h"

AudioUnitManifest::AudioUnitManifest(
        const QString& id, AVAudioUnitComponent* component) {
    setBackendType(EffectBackendType::AudioUnit);

    setId(id);
    setName(QString::fromNSString([component name]));
    setVersion(QString::fromNSString([component versionString]));
    setDescription(QString::fromNSString([component typeName]));
    setAuthor(QString::fromNSString([component manufacturerName]));

    // Try instantiating the unit in-process to fetch its properties quickly

    AudioUnitManager manager{component, AudioUnitInstantiationType::Sync};
    AUAudioUnit* audioUnit = manager.getAudioUnit();

    if (audioUnit) {
        AUParameterTree* parameterTree = [audioUnit parameterTree];
        NSArray<AUParameter*>* parameters = [parameterTree allParameters];

        // Resolve parameters
        bool hasLinkedParam = false;
        for (AUParameter* parameter in parameters) {
            QString paramName = QString::fromNSString([parameter displayName]);
            auto paramId = QString::fromNSString([parameter identifier]);
            auto paramFlags = [parameter flags];

            qDebug() << QString::fromNSString([component name])
                     << "has parameter" << paramName;

            // TODO: Check CanRamp too?
            if (paramFlags & kAudioUnitParameterFlag_IsWritable) {
                EffectManifestParameterPointer manifestParam = addParameter();
                manifestParam->setId(paramId);
                manifestParam->setName(paramName);
                manifestParam->setRange([parameter minValue],
                        [parameter value],
                        [parameter maxValue]);

                // Link the first parameter
                // TODO: Figure out if AU plugins provide a better way to figure
                // out the "default" parameter
                if (!hasLinkedParam) {
                    manifestParam->setDefaultLinkType(
                            EffectManifestParameter::LinkType::Linked);
                    hasLinkedParam = true;
                }

                // TODO: Support more modes, e.g. squared, square root in Mixxx
                if (paramFlags & kAudioUnitParameterFlag_DisplayLogarithmic) {
                    manifestParam->setValueScaler(
                            EffectManifestParameter::ValueScaler::Logarithmic);
                } else {
                    manifestParam->setValueScaler(
                            EffectManifestParameter::ValueScaler::Linear);
                }
            }
        }
    }
}
