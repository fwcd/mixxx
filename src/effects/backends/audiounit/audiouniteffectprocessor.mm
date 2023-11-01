#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioTypes/CoreAudioBaseTypes.h>
#include <CoreAudioTypes/CoreAudioTypes.h>

#include <QMutex>
#include <QtGlobal>

#include "effects/backends/audiounit/audiouniteffectprocessor.h"
#include "engine/effects/engineeffectparameter.h"
#include "engine/engine.h"
#include "util/assert.h"

AudioUnitEffectGroupState::AudioUnitEffectGroupState(
        const mixxx::EngineParameters& engineParameters)
        : EffectState(engineParameters),
          m_timestamp{
                  .mSampleTime = 0,
                  .mFlags = kAudioTimeStampSampleTimeValid,
          } {
    m_inputBuffers.mNumberBuffers = 1;
    m_outputBuffers.mNumberBuffers = 1;
}

// static
OSStatus AudioUnitEffectGroupState::renderCallbackUntyped(
        void* _Nonnull rawThis,
        AudioUnitRenderActionFlags* _Nonnull inActionFlags,
        const AudioTimeStamp* _Nonnull inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumFrames,
        AudioBufferList* _Nonnull ioData) {
    return static_cast<AudioUnitEffectGroupState*>(rawThis)->renderCallback(
            inActionFlags, inTimeStamp, inBusNumber, inNumFrames, ioData);
}

OSStatus AudioUnitEffectGroupState::renderCallback(AudioUnitRenderActionFlags*,
        const AudioTimeStamp*,
        UInt32,
        UInt32,
        AudioBufferList* ioData) const {
    if (ioData->mNumberBuffers == 0) {
        qWarning() << "Audio unit render callback failed, no buffers available "
                      "to write to.";
        return noErr;
    }
    VERIFY_OR_DEBUG_ASSERT(m_inputBuffers.mNumberBuffers > 0) {
        qWarning() << "Audio unit render callback failed, no buffers available "
                      "to read from.";
        return noErr;
    }
    ioData->mBuffers[0].mData = m_inputBuffers.mBuffers[0].mData;
    return noErr;
}

void AudioUnitEffectGroupState::render(AURenderBlock _Nonnull renderBlock,
        SINT sampleCount,
        const CSAMPLE* _Nonnull pInput,
        CSAMPLE* _Nonnull pOutput) {
    // Fill the input and output buffers.
    // TODO: Assert the size
    SINT size = sizeof(CSAMPLE) * sampleCount;
    m_inputBuffers.mBuffers[0].mData = const_cast<CSAMPLE*>(pInput);
    m_inputBuffers.mBuffers[0].mDataByteSize = size;
    m_outputBuffers.mBuffers[0].mData = pOutput;
    m_outputBuffers.mBuffers[0].mDataByteSize = size;

    // Set the render callback
    AURenderPullInputBlock pullInputBlock =
            ^(AudioUnitRenderActionFlags* _Nonnull flags,
                    const AudioTimeStamp* _Nonnull timestamp,
                    AUAudioFrameCount frameCount,
                    NSInteger inputBusNumber,
                    AudioBufferList* _Nonnull inputData) {
              return renderCallback(
                      flags, timestamp, inputBusNumber, frameCount, inputData);
            };

    // Apply the actual effect to the sample.
    AudioUnitRenderActionFlags flags = 0;
    NSInteger outputBusNumber = 0;
    OSStatus renderStatus = renderBlock(&flags,
            &m_timestamp,
            sampleCount,
            outputBusNumber,
            &m_outputBuffers,
            pullInputBlock);
    if (renderStatus != noErr) {
        qWarning() << "Rendering Audio Unit failed with status" << renderStatus;
        return;
    }

    // Increment the timestamp
    m_timestamp.mSampleTime += sampleCount;
}

AudioUnitEffectProcessor::AudioUnitEffectProcessor(
        AVAudioUnitComponent* _Nullable component)
        : m_manager(component) {
}

void AudioUnitEffectProcessor::loadEngineEffectParameters(
        const QMap<QString, EngineEffectParameterPointer>& parameters) {
    m_parameters = parameters.values();
}

void AudioUnitEffectProcessor::processChannel(
        AudioUnitEffectGroupState* _Nonnull channelState,
        const CSAMPLE* _Nonnull pInput,
        CSAMPLE* _Nonnull pOutput,
        const mixxx::EngineParameters& engineParameters,
        const EffectEnableState,
        const GroupFeatureState&) {
    AURenderBlock _Nullable renderBlock = m_manager.getRenderBlock();
    if (!renderBlock) {
        qWarning()
                << "Cannot process channel before Audio Unit is instantiated";
        return;
    }

    // Sync engine parameters with Audio Unit
    syncStreamFormat(engineParameters);

    // Sync effect parameters with Audio Unit
    syncParameters();

    // Render the effect into the output buffer
    channelState->render(
            renderBlock, engineParameters.samplesPerBuffer(), pInput, pOutput);
}

void AudioUnitEffectProcessor::syncParameters() {
    AUAudioUnit* _Nullable audioUnit = m_manager.getAudioUnit();
    DEBUG_ASSERT(audioUnit != nil);

    AUParameterTree* parameterTree = [audioUnit parameterTree];

    m_lastValues.reserve(m_parameters.size());

    int i = 0;
    for (auto parameter : m_parameters) {
        if (m_lastValues.size() < i) {
            m_lastValues.push_back(NAN);
        }
        DEBUG_ASSERT(m_lastValues.size() >= i);

        AudioUnitParameterID id = parameter->id().toInt();
        auto value = static_cast<AudioUnitParameterValue>(parameter->value());

        // Update parameter iff changed since the last sync
        if (m_lastValues[i] != value) {
            m_lastValues[i] = value;

            AUParameter* auParameter =
                    [parameterTree parameterWithID:id
                                             scope:kAudioUnitScope_Global
                                           element:0];
            if (auParameter != nil) {
                [auParameter setValue:value];
            } else {
                qWarning() << "Could not set parameter with id" << id;
            }
        }

        i++;
    }
}

void AudioUnitEffectProcessor::syncStreamFormat(
        const mixxx::EngineParameters& parameters) {
    AUAudioUnit* _Nullable audioUnit = m_manager.getAudioUnit();
    DEBUG_ASSERT(audioUnit != nil);

    if (parameters.sampleRate() != m_lastSampleRate ||
            parameters.channelCount() != m_lastChannelCount) {
        auto sampleRate = parameters.sampleRate();
        auto channelCount = parameters.channelCount();

        m_lastSampleRate = sampleRate;
        m_lastChannelCount = channelCount;

        AVAudioFormat* audioFormat = [[AVAudioFormat alloc]
                initWithCommonFormat:AVAudioPCMFormatFloat32
                          sampleRate:sampleRate
                            channels:channelCount
                         interleaved:false];

        qDebug() << "Updating Audio Unit stream format to sample rate"
                 << sampleRate << "and channel count" << channelCount;

        for (AUAudioUnitBusArray* buses in
                @[ [audioUnit inputBusses], [audioUnit outputBusses] ]) {
            for (AUAudioUnitBus* bus in buses) {
                NSError* error = nil;
                [bus setFormat:audioFormat error:&error];

                if (error != nil) {
                    qWarning()
                            << "Could not set Audio Unit stream format to "
                               "sample "
                               "rate"
                            << sampleRate << "and channel count" << channelCount
                            << ":" << [error localizedDescription];
                }
            }
        }
    }
}
