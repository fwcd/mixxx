#pragma once

#include <QWidget>

#include "library/itunes/ui_dlgitunes.h"
#include "library/library.h"
#include "library/libraryview.h"
#include "widget/wlibrary.h"
#include "widget/wtracktableview.h"

class DlgITunes : public QWidget, public Ui::DlgITunes, public virtual LibraryView {
    Q_OBJECT
  public:
    DlgITunes(WLibrary* parent, UserSettingsPointer pConfig, Library* pLibrary);
    ~DlgITunes() override;

    void onShow() override;
    bool hasFocus() const override;

  private:
    WTrackTableView* m_pTrackTableView;
};
