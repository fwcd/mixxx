#pragma once

#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudioTypes/CoreAudioTypes.h>
#import <dispatch/dispatch.h>

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
    ///
    /// Non-blocking and thread-safe, since this method is intended to (also) be
    /// called in a real-time context, e.g. from an audio thread, where we don't
    /// want to e.g. block on a mutex.
    AudioUnit _Nullable getAudioUnit();

    /// Waits for the audio unit to be instantiated.
    ///
    /// Returns true if successfully instantiated and false if the timeout was
    /// reached instead.
    bool waitForAudioUnit(int timeoutMs);

  private:
    QString m_name;
    std::atomic<bool> m_isInstantiated;
    dispatch_group_t _Nonnull m_instantiationGroup;
    AudioUnit _Nullable m_audioUnit;

    void instantiateAudioUnitAsync(AVAudioUnitComponent* _Nonnull component, bool inProcess);
    void instantiateAudioUnitSync(AVAudioUnitComponent* _Nonnull component);

    void initializeWith(AudioUnit _Nonnull audioUnit);
};
