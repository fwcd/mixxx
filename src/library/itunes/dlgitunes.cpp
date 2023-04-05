#include "library/itunes/dlgitunes.h"

#include <qwidget.h>

#include "widget/wtracktableview.h"

DlgITunes::DlgITunes(
        WLibrary* parent, UserSettingsPointer pConfig, Library* pLibrary)
        : QWidget(parent),
          m_pTrackTableView(new WTrackTableView(this,
                  pConfig,
                  pLibrary,
                  parent->getTrackTableBackgroundColorOpacity(),
                  true)) {
}

DlgITunes::~DlgITunes() {
}

void DlgITunes::onShow() {
    // TODO
}

bool DlgITunes::hasFocus() const {
    return m_pTrackTableView->hasFocus();
}
