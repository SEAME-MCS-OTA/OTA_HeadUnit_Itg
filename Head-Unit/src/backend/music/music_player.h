#ifndef BACKEND_MUSIC_MUSIC_PLAYER_H
#define BACKEND_MUSIC_MUSIC_PLAYER_H

#include <QObject>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QString>
#include <QStringList>

#include <memory>

/**
 * @brief MusicPlayer provides a simple playlist-backed audio player that can be
 *        consumed from QML. The library is loaded from disk on demand and
 *        exposes helpers to control playback and to discover available tracks.
 */
class MusicPlayer : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList tracks READ tracks NOTIFY tracksChanged)
    Q_PROPERTY(QString currentTrack READ currentTrack NOTIFY currentTrackChanged)
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)

public:
    explicit MusicPlayer(QObject* parent = nullptr);

    QStringList tracks() const;
    QString currentTrack() const;
    bool isPlaying() const;
    qint64 duration() const;
    qint64 position() const;
    qreal progress() const;

    Q_INVOKABLE void loadLibrary(const QString& path = QString());
    Q_INVOKABLE void play(const QString& track = QString());
    Q_INVOKABLE void pause();
    Q_INVOKABLE void toggle(const QString& track);
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

signals:
    void tracksChanged();
    void currentTrackChanged();
    void playingChanged();
    void durationChanged();
    void positionChanged();
    void progressChanged();
    void playbackError(const QString& message);

private slots:
    void handleStateChanged(QMediaPlayer::PlaybackState state);
    void handleErrorOccurred(QMediaPlayer::Error error, const QString& errorString);
    void handleDurationChanged(qint64 duration);
    void handlePositionChanged(qint64 position);
    void handleMediaStatusChanged(QMediaPlayer::MediaStatus status);

private:
    void ensureLibraryLoaded();
    QString resolveLibraryPath(const QString& path) const;
    int findTrackIndex(const QString& track) const;
    void updateCurrentTrack(int index);
    void playAtIndex(int index);

    QMediaPlayer player_;
    std::unique_ptr<QAudioOutput> audioOutput_;
    QStringList tracks_;
    QStringList trackPaths_;
    QString currentTrack_;
    bool playing_ = false;
    QString libraryPath_;
    int currentIndex_ = -1;
    qint64 duration_ = 0;
    qint64 position_ = 0;
};

#endif // BACKEND_MUSIC_MUSIC_PLAYER_H
