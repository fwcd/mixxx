#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include "util/assert.h"

#include <QString>

#include "effects/backends/audiounit/audiounitmanager.h"

AudioUnitManager::AudioUnitManager(AVAudioUnitComponent* _Nullable component,
        AudioUnitInstantiationType instantiationType)
        : m_name(QString::fromNSString([component name])),
          m_audioUnit(nil),
          m_renderBlock(nil) {
    // NOTE: The component can be null if the lookup failed in
    // `AudioUnitBackend::createProcessor`, in which case the effect simply acts
    // as an identity function on the audio. Same applies when
    // `AudioUnitManager` is default-initialized.
    if (!component) {
        return;
    }

    switch (instantiationType) {
    case Sync:
        instantiateAudioUnitSync(component);
        break;
    case AsyncInProcess:
    case AsyncOutOfProcess:
        instantiateAudioUnitAsync(
                component, instantiationType == AsyncInProcess);
        break;
    }
}

AudioUnitManager::~AudioUnitManager() {
    if (m_isInstantiated.load()) {
        qDebug() << "Uninitializing and disposing of Audio Unit" << m_name;
        [m_audioUnit deallocateRenderResources];
    }
}

AUAudioUnit* _Nullable AudioUnitManager::getAudioUnit() {
    // We need to load this atomic flag to ensure that we don't get a partial
    // read of the audio unit pointer (probably extremely uncommon, but not
    // impossible: https://belkadan.com/blog/2023/10/Implicity-Atomic)
    if (!m_isInstantiated.load()) {
        return nil;
    }
    return m_audioUnit;
}

AURenderBlock _Nullable AudioUnitManager::getRenderBlock() {
    if (!m_isInstantiated.load()) {
        return nil;
    }
    return m_renderBlock;
}

void AudioUnitManager::instantiateAudioUnitAsync(
        AVAudioUnitComponent* _Nonnull component, bool inProcess) {
    auto options = inProcess ? kAudioComponentInstantiation_LoadInProcess
                             : kAudioComponentInstantiation_LoadOutOfProcess;

    // Instantiate the audio unit asynchronously.
    qDebug() << "Instantiating Audio Unit" << m_name << "asynchronously";

    // TODO: Fix the weird formatting of blocks
    // clang-format off
    [AUAudioUnit instantiateWithComponentDescription:[component audioComponentDescription]
                                             options:options
                                   completionHandler:^(AUAudioUnit* _Nullable audioUnit, NSError* error) {
        if (error != nil) {
            qWarning() << "Could not instantiate Audio Unit" << m_name << ":" << [error localizedDescription];
            return;
        }

        VERIFY_OR_DEBUG_ASSERT(audioUnit != nil) {
            qWarning() << "Could not instantiate Audio Unit" << m_name << "...but the error is noErr, what's going on?";
            return;
        }

        initializeWith(audioUnit);
    }];
    // clang-format on
}

void AudioUnitManager::instantiateAudioUnitSync(
        AVAudioUnitComponent* _Nonnull component) {
    NSError* _Nullable error = nil;
    AUAudioUnit* _Nullable audioUnit = [[AUAudioUnit alloc]
            initWithComponentDescription:[component audioComponentDescription]
                                   error:&error];
    if (error != nil) {
        qWarning() << "Audio Unit" << m_name << "could not be instantiated:" <<
                [error localizedDescription];
    }

    initializeWith(audioUnit);
}

void AudioUnitManager::initializeWith(AUAudioUnit* _Nonnull audioUnit) {
    VERIFY_OR_DEBUG_ASSERT(!m_isInstantiated.load()) {
        qWarning() << "Audio Unit" << m_name
                   << "cannot be initialized after already having been "
                      "instantiated";
        return;
    }

    NSError* initError = nil;
    [audioUnit allocateRenderResourcesAndReturnError:&initError];
    if (initError != nil) {
        qWarning() << "Audio Unit" << m_name
                   << "failed to initialize, i.e. allocate render resources:" <<
                [initError localizedDescription];
        return;
    }

    m_audioUnit = audioUnit;
    // Cache the render block as per the docs:
    // https://developer.apple.com/documentation/audiotoolbox/auaudiounit/1387687-renderblock?language=objc
    m_renderBlock = [audioUnit renderBlock];
    m_isInstantiated.store(true);
}
