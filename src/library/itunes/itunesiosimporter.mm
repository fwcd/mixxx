#include "library/itunes/itunesiosimporter.h"

#import <MediaPlayer/MediaPlayer.h>
#include <gsl/pointers>

#include <QDateTime>
#include <QHash>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QString>
#include <QVariant>
#include <algorithm>
#include <atomic>
#include <map>
#include <memory>
#include <optional>
#include <utility>

#include "library/itunes/itunesdao.h"
#include "library/itunes/itunesfeature.h"
#include "library/queryutil.h"
#include "library/treeitem.h"
#include "library/treeitemmodel.h"

namespace {

class ImporterImpl {
  public:
    ImporterImpl(ITunesIOSImporter* pImporter, ITunesDAO& dao)
            : m_pImporter(pImporter), m_dao(dao) {
    }

    void importCollections(NSArray<MPMediaItemCollection*>* collections) {
        qDebug() << "Importing collections via native Media Player framework";

        // We prefer Objective-C-style for-in loops over C++ loops when dealing
        // with Objective-C types (both here and in the methods below) since
        // they use Objective-C's enumeration protocols and are guaranteed to
        // interact well with Objective-C collections.

        for (MPMediaItemCollection* collection in collections) {
            if (m_pImporter->canceled()) {
                break;
            }

            if ([collection isKindOfClass:[MPMediaPlaylist class]]) {
                importPlaylist((MPMediaPlaylist*) collection);
            }
        }
    }

    void importMediaItems(NSArray<MPMediaItem*>* items) {
        qDebug() << "Importing media items via native Media Player framework";

        for (MPMediaItem* item in items) {
            if (m_pImporter->canceled()) {
                break;
            }

            importMediaItem(item);
        }
    }

    void appendPlaylistTree(gsl::not_null<TreeItem*> item) {
        m_dao.appendPlaylistTree(item);
    }

  private:
    ITunesIOSImporter* m_pImporter;

    QHash<MPMediaEntityPersistentID, int> m_dbIdByPersistentId;
    ITunesDAO& m_dao;

    int dbIdFromPersistentId(MPMediaEntityPersistentID persistentId) {
        // Map a persistent ID as used by iTunes to an (incrementing) database
        // ID The persistent IDs used by iTunes occasionally exceed signed
        // 64-bit ints, so we cannot use them directly, unfortunately (also we
        // currently use the fact that our deterministic indexing scheme starts
        // at 0 to represent the root of the playlist tree with -1 in
        // appendPlaylistTree).
        auto existing = m_dbIdByPersistentId.find(persistentId);
        if (existing != m_dbIdByPersistentId.end()) {
            return existing.value();
        } else {
            int dbId = m_dbIdByPersistentId.size();
            m_dbIdByPersistentId[persistentId] = dbId;
            return dbId;
        }
    }

    void importPlaylist(MPMediaPlaylist* mpPlaylist) {
        int playlistId = dbIdFromPersistentId(mpPlaylist.persistentID);
        // TODO: Figure out if we can infer a hierarchy or if the API even provides folders
        int parentId = kRootITunesPlaylistId;

        ITunesPlaylist playlist = {
                .id = playlistId,
                .name = QString::fromNSString(mpPlaylist.name),
        };
        if (!m_dao.importPlaylist(playlist)) {
            return;
        }

        if (!m_dao.importPlaylistRelation(parentId, playlistId)) {
            return;
        }

        int i = 0;
        for (MPMediaItem* item in mpPlaylist.items) {
            if (m_pImporter->canceled()) {
                return;
            }

            int trackId = dbIdFromPersistentId(item.persistentID);
            if (!m_dao.importPlaylistTrack(playlistId, trackId, i)) {
                return;
            }

            i++;
        }
    }

    void importMediaItem(MPMediaItem* item) {
        // Skip DRM-protected and non-downloaded tracks
        // TODO: Is this correct? Is `isCloudItem` guaranteed to be false if downloaded?
        if (item.hasProtectedAsset || item.isCloudItem) {
            return;
        }

        ITunesTrack track = {
                .id = dbIdFromPersistentId(item.persistentID),
                .artist = QString::fromNSString(item.artist),
                .title = QString::fromNSString(item.title),
                .album = QString::fromNSString(item.albumTitle),
                .albumArtist = QString::fromNSString(item.albumArtist),
                .composer = QString::fromNSString(item.composer),
                .genre = QString::fromNSString(item.genre),
                .grouping = QString::fromNSString(item.userGrouping),
                .year = 0, // TODO: Infer from releaseDate?
                .duration = static_cast<int>(item.playbackDuration / 1000),
                .location = QString::fromNSString(item.assetURL.path),
                .rating = static_cast<int>(item.rating / 20),
                .comment = QString::fromNSString(item.comments),
                .trackNumber = static_cast<int>(item.albumTrackNumber),
                .bpm = static_cast<int>(item.beatsPerMinute),
                .bitrate = 0,
                .playCount = static_cast<int>(item.playCount),
                .lastPlayedAt = QDateTime::fromNSDate(item.lastPlayedDate),
                .dateAdded = QDateTime::fromNSDate(item.dateAdded),
        };

        if (!m_dao.importTrack(track)) {
            return;
        }
    }
};

} // anonymous namespace

ITunesIOSImporter::ITunesIOSImporter(
        ITunesFeature* pParentFeature, std::unique_ptr<ITunesDAO> dao)
        : ITunesImporter(pParentFeature), m_dao(std::move(dao)) {
}

ITunesImport ITunesIOSImporter::importLibrary() {
    ITunesImport iTunesImport;

    std::unique_ptr<TreeItem> rootItem =
            TreeItem::newRoot(m_pParentFeature);
    ImporterImpl impl(this, *m_dao);

    impl.importCollections([MPMediaQuery playlistsQuery].collections);
    impl.importMediaItems([MPMediaQuery songsQuery].items);
    impl.appendPlaylistTree(rootItem.get());

    iTunesImport.playlistRoot = std::move(rootItem);

    return iTunesImport;
}
