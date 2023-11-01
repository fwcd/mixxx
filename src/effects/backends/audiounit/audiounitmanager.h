#pragma once

#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioTypes/CoreAudioTypes.h>

#include <QString>

enum AudioUnitInstantiationType {
    Sync,
    AsyncInProcess,
    AsyncOutOfProcess,
};

/// A RAII wrapper around an `AudioUnit`.
class AudioUnitManager {
  public:
    AudioUnitManager(AVAudioUnitComponent* _Nullable component = nil,
            AudioUnitInstantiationType instantiationType =
                    AudioUnitInstantiationType::AsyncOutOfProcess);
    ~AudioUnitManager();

    AudioUnitManager(const AudioUnitManager&) = delete;
    AudioUnitManager& operator=(const AudioUnitManager&) = delete;

    /// Fetches the audio unit if already instantiated.
    /// Non-blocking and thread-safe.
    AUAudioUnit* _Nullable getAudioUnit();

    /// Fetches the render block if already instantiated.
    /// Non-blocking and thread-safe.
    AURenderBlock _Nullable getRenderBlock();

  private:
    QString m_name;
    std::atomic<bool> m_isInstantiated;
    AUAudioUnit* _Nullable m_audioUnit;
    AURenderBlock _Nullable m_renderBlock;

    void instantiateAudioUnitAsync(AVAudioUnitComponent* _Nonnull component, bool inProcess);
    void instantiateAudioUnitSync(AVAudioUnitComponent* _Nonnull component);

    void initializeWith(AUAudioUnit* _Nonnull audioUnit);
};
