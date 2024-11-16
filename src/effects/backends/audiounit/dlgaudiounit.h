#pragma once

#include "effects/dlgeffect.h"

class AudioUnitManager;

/// A dialog hosting the UI of an Audio Unit.
class DlgAudioUnit : public DlgEffect {
    Q_OBJECT

  public:
    DlgAudioUnit(const AudioUnitManager& manager);
    virtual ~DlgAudioUnit();

  private:
    id m_resizeObserver;
};
