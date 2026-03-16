#include "music_player.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
#include <QStandardPaths>

namespace {
QStringList audioFilters();

bool containsAudioFiles(const QDir& directory) {
    if (!directory.exists()) {
        return false;
    }
    const QFileInfoList entries = directory.entryInfoList(audioFilters(),
                                                          QDir::Files | QDir::Readable | QDir::NoSymLinks,
                                                          QDir::Name | QDir::IgnoreCase);
    return !entries.isEmpty();
}

QString defaultLibraryPath() {
    const QString envPath = qEnvironmentVariable("HEADUNIT_MUSIC_DIR");
    if (!envPath.isEmpty()) {
        QDir envDir(envPath);
        if (containsAudioFiles(envDir)) {
            return envDir.absolutePath();
        }
    }

    const QString appDir = QCoreApplication::applicationDirPath();
    const QStringList relativeCandidates = {
        QStringLiteral("../design/assets/music"),
        QStringLiteral("../../design/assets/music"),
        QStringLiteral("../../../design/assets/music"),
        QStringLiteral("../design/assets"),
        QStringLiteral("../../design/assets"),
        QStringLiteral("../../../design/assets"),
        QStringLiteral("../assets/music"),
        QStringLiteral("../../assets/music"),
        QStringLiteral("assets/music"),
        QStringLiteral("../assets"),
        QStringLiteral("../../assets"),
        QStringLiteral("assets")
    };

    for (const QString& rel : relativeCandidates) {
        QDir candidate(appDir);
        if (candidate.cd(rel) && containsAudioFiles(candidate)) {
            return candidate.absolutePath();
        }
    }

    const QStringList standard = QStandardPaths::standardLocations(QStandardPaths::MusicLocation);
    for (const QString& path : standard) {
        QDir candidate(path);
        if (containsAudioFiles(candidate)) {
            return candidate.absolutePath();
        }
    }

    // Fallback: if no directory contains audio, prefer env/app relative path even without files.
    if (!envPath.isEmpty()) {
        QDir envDir(envPath);
        if (envDir.exists()) {
            return envDir.absolutePath();
        }
    }

    for (const QString& rel : relativeCandidates) {
        QDir candidate(appDir);
        if (candidate.cd(rel)) {
            return candidate.absolutePath();
        }
    }

    return appDir;
}

QStringList audioFilters() {
    return {"*.mp3", "*.wav", "*.ogg", "*.flac"};
}
} // namespace

MusicPlayer::MusicPlayer(QObject* parent)
    : QObject(parent)
    , audioOutput_(std::make_unique<QAudioOutput>()) {
    player_.setAudioOutput(audioOutput_.get());
    connect(&player_, &QMediaPlayer::playbackStateChanged,
            this, &MusicPlayer::handleStateChanged);
    connect(&player_, &QMediaPlayer::errorOccurred,
            this, &MusicPlayer::handleErrorOccurred);
    connect(&player_, &QMediaPlayer::durationChanged,
            this, &MusicPlayer::handleDurationChanged);
    connect(&player_, &QMediaPlayer::positionChanged,
            this, &MusicPlayer::handlePositionChanged);
    connect(&player_, &QMediaPlayer::mediaStatusChanged,
            this, &MusicPlayer::handleMediaStatusChanged);
}

QStringList MusicPlayer::tracks() const {
    return tracks_;
}

QString MusicPlayer::currentTrack() const {
    return currentTrack_;
}

bool MusicPlayer::isPlaying() const {
    return playing_;
}

qint64 MusicPlayer::duration() const {
    return duration_;
}

qint64 MusicPlayer::position() const {
    return position_;
}

qreal MusicPlayer::progress() const {
    if (duration_ <= 0) {
        return 0.0;
    }
    return static_cast<qreal>(position_) / static_cast<qreal>(duration_);
}

void MusicPlayer::loadLibrary(const QString& path) {
    const QString resolved = resolveLibraryPath(path);
    QDir musicDir(resolved);
    const QFileInfoList entries = musicDir.entryInfoList(audioFilters(),
                                                         QDir::Files | QDir::Readable | QDir::NoSymLinks,
                                                         QDir::Name | QDir::IgnoreCase);

    tracks_.clear();
    trackPaths_.clear();

    for (const QFileInfo& fileInfo : entries) {
        tracks_.push_back(fileInfo.fileName());
        trackPaths_.push_back(fileInfo.absoluteFilePath());
    }

    libraryPath_ = resolved;

    emit tracksChanged();

    if (!tracks_.isEmpty()) {
        updateCurrentTrack(0);
    } else {
        updateCurrentTrack(-1);
    }
}

void MusicPlayer::play(const QString& track) {
    ensureLibraryLoaded();

    if (tracks_.isEmpty()) {
        emit playbackError(tr("No audio tracks available in %1").arg(libraryPath_));
        return;
    }

    int index = track.isEmpty() ? currentIndex_ : findTrackIndex(track);
    if (index < 0) {
        index = !tracks_.isEmpty() ? 0 : -1;
    }

    if (index < 0) {
        emit playbackError(tr("Track %1 not found in library").arg(track));
        return;
    }

    playAtIndex(index);
}

void MusicPlayer::pause() {
    player_.pause();
}

void MusicPlayer::toggle(const QString& track) {
    if (!track.isEmpty() && track != currentTrack_) {
        play(track);
        return;
    }

    if (isPlaying()) {
        pause();
    } else {
        play(track);
    }
}

void MusicPlayer::next() {
    ensureLibraryLoaded();
    if (tracks_.isEmpty()) {
        return;
    }
    int nextIndex = (currentIndex_ + 1) % tracks_.size();
    playAtIndex(nextIndex);
}

void MusicPlayer::previous() {
    ensureLibraryLoaded();
    if (tracks_.isEmpty()) {
        return;
    }
    int previousIndex = currentIndex_ - 1;
    if (previousIndex < 0) {
        previousIndex = tracks_.size() - 1;
    }
    playAtIndex(previousIndex);
}

void MusicPlayer::handleStateChanged(QMediaPlayer::PlaybackState state) {
    const bool playingNow = (state == QMediaPlayer::PlayingState);
    if (playing_ == playingNow) {
        if (state != QMediaPlayer::StoppedState) {
            return;
        }
    } else {
        playing_ = playingNow;
        emit playingChanged();
    }

    if (state == QMediaPlayer::StoppedState) {
        handlePositionChanged(0);
    }
}

void MusicPlayer::handleErrorOccurred(QMediaPlayer::Error error, const QString& errorString) {
    Q_UNUSED(error);
    emit playbackError(errorString);
}

void MusicPlayer::handleDurationChanged(qint64 duration) {
    if (duration_ == duration) {
        return;
    }
    duration_ = duration;
    emit durationChanged();
    emit progressChanged();
}

void MusicPlayer::handlePositionChanged(qint64 position) {
    if (position_ == position) {
        return;
    }
    position_ = position;
    emit positionChanged();
    emit progressChanged();
}

void MusicPlayer::handleMediaStatusChanged(QMediaPlayer::MediaStatus status) {
    if (status == QMediaPlayer::LoadedMedia || status == QMediaPlayer::BufferedMedia) {
        const qint64 currentDuration = player_.duration();
        if (currentDuration != duration_) {
            duration_ = currentDuration;
            emit durationChanged();
            emit progressChanged();
        }
    }
}
void MusicPlayer::ensureLibraryLoaded() {
    if (!tracks_.isEmpty() || !libraryPath_.isEmpty()) {
        return;
    }
    loadLibrary(QString());
}

QString MusicPlayer::resolveLibraryPath(const QString& path) const {
    if (!path.isEmpty()) {
        return path;
    }
    if (!libraryPath_.isEmpty()) {
        return libraryPath_;
    }
    return defaultLibraryPath();
}

int MusicPlayer::findTrackIndex(const QString& track) const {
    return tracks_.indexOf(track);
}

void MusicPlayer::updateCurrentTrack(int index) {
    QString nextTrack;
    if (index >= 0 && index < tracks_.size()) {
        nextTrack = tracks_.at(index);
    }

    if (currentTrack_ == nextTrack) {
        return;
    }

    currentTrack_ = nextTrack;
    currentIndex_ = index;
    emit currentTrackChanged();

    if (position_ != 0) {
        position_ = 0;
        emit positionChanged();
        emit progressChanged();
    }

    if (duration_ != 0) {
        duration_ = 0;
        emit durationChanged();
        emit progressChanged();
    }
}

void MusicPlayer::playAtIndex(int index) {
    if (index < 0 || index >= trackPaths_.size()) {
        emit playbackError(tr("Track index %1 is out of range").arg(index));
        return;
    }

    const QString filePath = trackPaths_.at(index);
    if (filePath.isEmpty()) {
        emit playbackError(tr("Track path is empty for index %1").arg(index));
        return;
    }

    if (player_.source().isEmpty() || currentIndex_ != index) {
        player_.setSource(QUrl::fromLocalFile(filePath));
    }

    updateCurrentTrack(index);
    player_.play();
}
