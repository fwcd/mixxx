#pragma once

#include <QDialog>

class AudioUnitManager;

/// A dialog hosting the UI of an Audio Unit.
class DlgAudioUnit : public QDialog {
    Q_OBJECT

  public:
    DlgAudioUnit(const AudioUnitManager& manager);
};
