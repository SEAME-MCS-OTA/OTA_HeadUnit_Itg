#ifndef BACKEND_BLUETOOTH_BLUETOOTH_AUDIO_PLAYER_H
#define BACKEND_BLUETOOTH_BLUETOOTH_AUDIO_PLAYER_H

#include <QObject>
#include <QString>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusServiceWatcher>
#include <QTimer>
#include <QNetworkAccessManager>
#include <QProcess>
#include <memory>
#include <QMap>
#include <QDBusObjectPath>

// Type definitions for BlueZ GetManagedObjects reply
using PropertyMap = QMap<QString, QVariant>;
using InterfaceMap = QMap<QString, PropertyMap>;
using ManagedObjectMap = QMap<QDBusObjectPath, InterfaceMap>;


/**
 * @brief BluetoothAudioPlayer handles media control for Bluetooth audio streaming
 *        using AVRCP (Audio/Video Remote Control Profile) via BlueZ D-Bus interface.
 *        Provides real-time metadata, playback control, and album art from connected phone.
 */
class BluetoothAudioPlayer : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool playing READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY trackTitleChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY trackArtistChanged)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY trackAlbumChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(bool hasAlbumArt READ hasAlbumArt NOTIFY albumArtChanged)
    Q_PROPERTY(QString albumArtPath READ albumArtPath NOTIFY albumArtChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)

public:
    explicit BluetoothAudioPlayer(QObject* parent = nullptr);
    ~BluetoothAudioPlayer();

    // Property getters
    bool isPlaying() const { return playing_; }
    QString status() const { return status_; }
    QString trackTitle() const { return trackTitle_; }
    QString trackArtist() const { return trackArtist_; }
    QString trackAlbum() const { return trackAlbum_; }
    qint64 duration() const { return duration_; }
    qint64 position() const { return position_; }
    bool hasAlbumArt() const { return hasAlbumArt_; }
    QString albumArtPath() const { return albumArtPath_; }
    bool isConnected() const { return connected_; }
    QString deviceName() const { return deviceName_; }
    int volume() const { return volume_; }
    void setVolume(int vol);

public slots:
    // Playback control (AVRCP commands via D-Bus)
    void play();
    void pause();
    void next();
    void previous();
    void stop();
    void seek(qint64 positionMs);

    // Connection management
    void setConnectedDevice(const QString& devicePath);
    void disconnectDevice();

signals:
    void playingChanged();
    void statusChanged();
    void trackTitleChanged();
    void trackArtistChanged();
    void trackAlbumChanged();
    void durationChanged();
    void positionChanged();
    void albumArtChanged();
    void connectedChanged();
    void deviceNameChanged();
    void volumeChanged();
    void errorOccurred(const QString& message);

private slots:
    void onMediaPlayerPropertiesChanged(const QString& interface,
                                       const QVariantMap& changedProperties,
                                       const QStringList& invalidatedProperties);
    void onMediaControlPropertiesChanged(const QString& interface,
                                         const QVariantMap& changedProperties,
                                         const QStringList& invalidatedProperties);
    void updatePosition();
    void onBlueZServiceOwnerChanged(const QString& service,
                                     const QString& oldOwner,
                                     const QString& newOwner);
    void onAlbumArtDownloaded(QNetworkReply* reply);

private:
    void setupDBusConnections();
    void cleanupDBusConnections();
    void discoverMediaPlayer();
    void updateMetadata(const QVariantMap& metadata);
    void downloadAlbumArt(const QString& artUrl);
    QString extractDeviceName(const QString& devicePath);
    void resetState();

    // PulseAudio local volume control
    QString getPulseAudioSourceName() const;
    void setPulseAudioVolume(int percent);
    int getPulseAudioVolume();

    // D-Bus interfaces
    std::unique_ptr<QDBusInterface> mediaPlayerInterface_;
    std::unique_ptr<QDBusInterface> mediaControlInterface_;
    QDBusServiceWatcher* serviceWatcher_;
    QNetworkAccessManager* networkManager_;

    // State
    bool playing_ = false;
    bool connected_ = false;
    QString status_ = "stopped";
    QString trackTitle_ = "No Track";
    QString trackArtist_ = "Unknown Artist";
    QString trackAlbum_ = "Unknown Album";
    qint64 duration_ = 0;
    qint64 position_ = 0;
    bool hasAlbumArt_ = false;
    QString albumArtPath_;
    QString devicePath_;
    QString deviceName_;
    QString mediaPlayerPath_;
    int volume_ = 50; // 0-127 (AVRCP range), expose as 0-100 to UI

    // Position update timer
    QTimer* positionTimer_;
    QTimer* mediaPlayerDiscoveryTimer_;
};

#endif // BACKEND_BLUETOOTH_BLUETOOTH_AUDIO_PLAYER_H
