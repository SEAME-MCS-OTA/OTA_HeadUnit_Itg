#include "bluetooth_audio_player.h"
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusArgument>
#include <QDBusObjectPath>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QUrl>
#include <QRegularExpression>

BluetoothAudioPlayer::BluetoothAudioPlayer(QObject* parent)
    : QObject(parent)
    , positionTimer_(new QTimer(this))
    , mediaPlayerDiscoveryTimer_(new QTimer(this))
    , networkManager_(new QNetworkAccessManager(this))
{
    qDBusRegisterMetaType<QVariantMap>();
    qDBusRegisterMetaType<InterfaceMap>();
    qDBusRegisterMetaType<ManagedObjectMap>();

    // Position update timer (1 second interval)
    positionTimer_->setInterval(1000);
    connect(positionTimer_, &QTimer::timeout, this, &BluetoothAudioPlayer::updatePosition);

    // Media player discovery timer
    mediaPlayerDiscoveryTimer_->setInterval(2000); // Try every 2 seconds
    connect(mediaPlayerDiscoveryTimer_, &QTimer::timeout, this, &BluetoothAudioPlayer::discoverMediaPlayer);

    // Monitor BlueZ service availability
    serviceWatcher_ = new QDBusServiceWatcher(
        "org.bluez",
        QDBusConnection::systemBus(),
        QDBusServiceWatcher::WatchForOwnerChange,
        this
    );
    connect(serviceWatcher_, &QDBusServiceWatcher::serviceOwnerChanged,
            this, &BluetoothAudioPlayer::onBlueZServiceOwnerChanged);

    // Network manager for album art download
    connect(networkManager_, &QNetworkAccessManager::finished,
            this, &BluetoothAudioPlayer::onAlbumArtDownloaded);

    setupDBusConnections();
    qDebug() << "[BluetoothAudioPlayer] Initialized with D-Bus AVRCP support";
}

BluetoothAudioPlayer::~BluetoothAudioPlayer()
{
    cleanupDBusConnections();
}

void BluetoothAudioPlayer::setupDBusConnections()
{
    // Connections will be established when device connects via setConnectedDevice()
}

void BluetoothAudioPlayer::cleanupDBusConnections()
{
    mediaPlayerInterface_.reset();
    mediaControlInterface_.reset();
    positionTimer_->stop();
    mediaPlayerDiscoveryTimer_->stop();
}

void BluetoothAudioPlayer::setConnectedDevice(const QString& devicePath)
{
    if (devicePath_ == devicePath) {
        return;
    }

    cleanupDBusConnections();

    devicePath_ = devicePath;

    if (!devicePath.isEmpty()) {
        deviceName_ = extractDeviceName(devicePath);
        qDebug() << "[BluetoothAudioPlayer] Device set:" << deviceName_ << "at" << devicePath;

        // Start discovering MediaPlayer interface
        mediaPlayerDiscoveryTimer_->start();

        connected_ = true;
    } else {
        deviceName_.clear();
        connected_ = false;
        resetState();
    }

    emit connectedChanged();
    emit deviceNameChanged();
}

void BluetoothAudioPlayer::discoverMediaPlayer()
{
    if (devicePath_.isEmpty() || !mediaPlayerPath_.isEmpty()) {
        return;
    }

    qDebug() << "[BluetoothAudioPlayer] Discovering MediaPlayer for device:" << devicePath_;

    QDBusInterface manager("org.bluez", "/", "org.freedesktop.DBus.ObjectManager", QDBusConnection::systemBus());
    QDBusReply<ManagedObjectMap> reply = manager.call("GetManagedObjects");

    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Failed to get managed objects:" << reply.error().message();
        return;
    }

    const auto& managedObjects = reply.value();

    for (auto it = managedObjects.constBegin(); it != managedObjects.constEnd(); ++it) {
        const QString &path = it.key().path();
        const InterfaceMap &interfaces = it.value();

        if (interfaces.contains(QStringLiteral("org.bluez.MediaPlayer1"))) {
            const PropertyMap &props = interfaces.value(QStringLiteral("org.bluez.MediaPlayer1"));
            QVariant deviceProp = props.value(QStringLiteral("Device"));
            QDBusObjectPath deviceObjectPath = deviceProp.value<QDBusObjectPath>();

            if (deviceObjectPath.path() == devicePath_) {
                mediaPlayerPath_ = path;
                qDebug() << "[BluetoothAudioPlayer] Found MediaPlayer at:" << path;

                mediaPlayerDiscoveryTimer_->stop();

                // Create interface for media player
                mediaPlayerInterface_ = std::make_unique<QDBusInterface>(
                    "org.bluez",
                    mediaPlayerPath_,
                    "org.bluez.MediaPlayer1",
                    QDBusConnection::systemBus()
                );

                if (!mediaPlayerInterface_->isValid()) {
                    qWarning() << "[BluetoothAudioPlayer] MediaPlayer interface invalid:" << mediaPlayerInterface_->lastError().message();
                    mediaPlayerPath_.clear(); // Clear path to allow rediscovery
                    return;
                }

                // Create interface for media control (volume)
                QString controlPath = deviceObjectPath.path(); // Use device path for MediaControl1
                mediaControlInterface_ = std::make_unique<QDBusInterface>(
                    "org.bluez",
                    controlPath,
                    "org.bluez.MediaControl1",
                    QDBusConnection::systemBus()
                );

                if (!mediaControlInterface_->isValid()) {
                    qWarning() << "[BluetoothAudioPlayer] MediaControl interface invalid:" << mediaControlInterface_->lastError().message();
                }

                // Subscribe to property changes for both interfaces
                QDBusConnection::systemBus().connect(
                    "org.bluez",
                    mediaPlayerPath_,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    this,
                    SLOT(onMediaPlayerPropertiesChanged(QString,QVariantMap,QStringList))
                );

                QDBusConnection::systemBus().connect(
                    "org.bluez",
                    controlPath,
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    this,
                    SLOT(onMediaControlPropertiesChanged(QString,QVariantMap,QStringList))
                );

                // Read initial properties from MediaPlayer1
                QVariant trackVar = mediaPlayerInterface_->property("Track");
                if (trackVar.isValid() && trackVar.canConvert<QDBusArgument>()) {
                    QDBusArgument trackArg = trackVar.value<QDBusArgument>();
                    QVariantMap trackMap;
                    trackArg >> trackMap;
                    updateMetadata(trackMap);
                }

                QVariant statusVar = mediaPlayerInterface_->property("Status");
                if (statusVar.isValid()) {
                    status_ = statusVar.toString();
                    playing_ = (status_ == "playing");
                    emit statusChanged();
                    emit playingChanged();

                    if (playing_) {
                        positionTimer_->start();
                    }
                }

                QVariant posVar = mediaPlayerInterface_->property("Position");
                if (posVar.isValid()) {
                    position_ = posVar.toUInt();
                    emit positionChanged();
                }

                // Get initial volume from PulseAudio source
                int pulseVolume = getPulseAudioVolume();
                if (pulseVolume >= 0) {
                    volume_ = pulseVolume;
                    emit volumeChanged();
                    qDebug() << "[BluetoothAudioPlayer] Initial PulseAudio volume:" << volume_ << "%";
                } else {
                    qDebug() << "[BluetoothAudioPlayer] Could not read initial volume, using default 50%";
                    volume_ = 50;
                }

                qDebug() << "[BluetoothAudioPlayer] MediaPlayer initialized. Status:" << status_;
                return; // Exit after finding the correct player
            }
        }
    }

    qWarning() << "[BluetoothAudioPlayer] No MediaPlayer found for device:" << devicePath_;
}

void BluetoothAudioPlayer::setVolume(int vol) {
    if (vol < 0) vol = 0;
    if (vol > 100) vol = 100;

    if (!connected_) {
        qWarning() << "[BluetoothAudioPlayer] Cannot set volume: not connected";
        return;
    }

    // Use PulseAudio local volume control instead of AVRCP
    setPulseAudioVolume(vol);

    // Update internal state and notify UI
    if (volume_ != vol) {
        volume_ = vol;
        emit volumeChanged();
    }
}

void BluetoothAudioPlayer::onMediaPlayerPropertiesChanged(
    const QString& interface,
    const QVariantMap& changedProperties,
    const QStringList& invalidatedProperties)
{
    Q_UNUSED(invalidatedProperties)

    if (interface != "org.bluez.MediaPlayer1") {
        return;
    }

    qDebug() << "[BluetoothAudioPlayer] MediaPlayer properties changed:" << changedProperties.keys();

    if (changedProperties.contains("Track")) {
        QVariant trackVariant = changedProperties.value("Track");
        if (trackVariant.canConvert<QDBusArgument>()) {
            QDBusArgument trackArg = trackVariant.value<QDBusArgument>();
            QVariantMap trackMap;
            trackArg >> trackMap;
            updateMetadata(trackMap);
        }
    }

    if (changedProperties.contains("Status")) {
        status_ = changedProperties.value("Status").toString();
        playing_ = (status_ == "playing");
        emit statusChanged();
        emit playingChanged();

        if (playing_) {
            positionTimer_->start();
        } else {
            positionTimer_->stop();
        }

        qDebug() << "[BluetoothAudioPlayer] Status changed to:" << status_;
    }

    if (changedProperties.contains("Position")) {
        position_ = changedProperties.value("Position").toULongLong();
        emit positionChanged();
    }
}

void BluetoothAudioPlayer::onMediaControlPropertiesChanged(
    const QString& interface,
    const QVariantMap& changedProperties,
    const QStringList& invalidatedProperties)
{
    Q_UNUSED(invalidatedProperties)

    if (interface != "org.bluez.MediaControl1") {
        return;
    }

    qDebug() << "[BluetoothAudioPlayer] MediaControl properties changed:" << changedProperties.keys();

    if (changedProperties.contains("Volume")) {
        quint16 avrcpVolume = changedProperties.value("Volume").toUInt();
        int newVolume = (avrcpVolume * 100) / 127;
        if (volume_ != newVolume) {
            volume_ = newVolume;
            emit volumeChanged();
            qDebug() << "[BluetoothAudioPlayer] Volume changed to:" << volume_ << "(AVRCP:" << avrcpVolume << ")";
        }
    }
}

void BluetoothAudioPlayer::updateMetadata(const QVariantMap& metadata)
{
    bool changed = false;

    qDebug() << "[BluetoothAudioPlayer] Metadata keys:" << metadata.keys();

    if (metadata.contains("Title")) {
        QString newTitle = metadata.value("Title").toString();
        if (trackTitle_ != newTitle) {
            trackTitle_ = newTitle;
            emit trackTitleChanged();
            changed = true;
        }
    }

    if (metadata.contains("Artist")) {
        QString newArtist = metadata.value("Artist").toString();
        if (trackArtist_ != newArtist) {
            trackArtist_ = newArtist;
            emit trackArtistChanged();
            changed = true;
        }
    }

    if (metadata.contains("Album")) {
        QString newAlbum = metadata.value("Album").toString();
        if (trackAlbum_ != newAlbum) {
            trackAlbum_ = newAlbum;
            emit trackAlbumChanged();
            changed = true;
        }
    }

    if (metadata.contains("Duration")) {
        qint64 newDuration = metadata.value("Duration").toLongLong();
        if (duration_ != newDuration) {
            duration_ = newDuration;
            emit durationChanged();
            changed = true;
        }
    }

    if (metadata.contains("AlbumArt")) {
        QString artUrl = metadata.value("AlbumArt").toString();
        downloadAlbumArt(artUrl);
    }

    if (changed) {
        qDebug() << "[BluetoothAudioPlayer] Metadata updated:"
                 << trackTitle_ << "-" << trackArtist_ << "-" << trackAlbum_;
    }
}

void BluetoothAudioPlayer::downloadAlbumArt(const QString& artUrl)
{
    if (artUrl.isEmpty()) {
        return;
    }

    qDebug() << "[BluetoothAudioPlayer] Album art URL:" << artUrl;

    // Handle local file:// URLs (most common from BlueZ)
    if (artUrl.startsWith("file://")) {
        QString localPath = artUrl.mid(7);
        if (QFile::exists(localPath)) {
            albumArtPath_ = localPath;
            hasAlbumArt_ = true;
            emit albumArtChanged();
            qDebug() << "[BluetoothAudioPlayer] Album art loaded from:" << localPath;
        } else {
            qWarning() << "[BluetoothAudioPlayer] Album art file not found:" << localPath;
        }
    }
    // Handle HTTP/HTTPS URLs
    else if (artUrl.startsWith("http://") || artUrl.startsWith("https://")) {
        QNetworkRequest request{QUrl(artUrl)};
        networkManager_->get(request);
    }
}

void BluetoothAudioPlayer::onAlbumArtDownloaded(QNetworkReply* reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[BluetoothAudioPlayer] Failed to download album art:"
                   << reply->errorString();
        reply->deleteLater();
        return;
    }

    QByteArray imageData = reply->readAll();
    reply->deleteLater();

    // Save to temp location
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QDir().mkpath(tempDir);
    QString artPath = tempDir + "/headunit_album_art.jpg";

    QFile file(artPath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(imageData);
        file.close();

        albumArtPath_ = artPath;
        hasAlbumArt_ = true;
        emit albumArtChanged();
        qDebug() << "[BluetoothAudioPlayer] Album art downloaded to:" << artPath;
    }
}

void BluetoothAudioPlayer::play()
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        emit errorOccurred("Not connected to media player");
        qWarning() << "[BluetoothAudioPlayer] Cannot play: no valid media player";
        return;
    }

    QDBusReply<void> reply = mediaPlayerInterface_->call(QDBus::NoBlock, "Play");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Play command failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothAudioPlayer] Play command sent";
    }
}

void BluetoothAudioPlayer::pause()
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        return;
    }

    QDBusReply<void> reply = mediaPlayerInterface_->call(QDBus::NoBlock, "Pause");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Pause command failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothAudioPlayer] Pause command sent";
    }
}

void BluetoothAudioPlayer::stop()
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        return;
    }

    QDBusReply<void> reply = mediaPlayerInterface_->call(QDBus::NoBlock, "Stop");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Stop command failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothAudioPlayer] Stop command sent";
    }
}

void BluetoothAudioPlayer::next()
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        return;
    }

    QDBusReply<void> reply = mediaPlayerInterface_->call(QDBus::NoBlock, "Next");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Next command failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothAudioPlayer] Next command sent";
    }
}

void BluetoothAudioPlayer::previous()
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        return;
    }

    QDBusReply<void> reply = mediaPlayerInterface_->call(QDBus::NoBlock, "Previous");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Previous command failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothAudioPlayer] Previous command sent";
    }
}

void BluetoothAudioPlayer::seek(qint64 positionMs)
{
    if (!mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Cannot seek: no valid media player";
        return;
    }

    // BlueZ MediaPlayer1 uses microseconds for position
    quint32 positionUs = static_cast<quint32>(positionMs * 1000);

    QDBusInterface propsInterface("org.bluez", mediaPlayerPath_,
                                  "org.freedesktop.DBus.Properties",
                                  QDBusConnection::systemBus());

    if (!propsInterface.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Invalid properties interface";
        return;
    }

    QDBusReply<void> reply = propsInterface.call(QDBus::NoBlock, "Set",
                                                  "org.bluez.MediaPlayer1",
                                                  "Position",
                                                  QVariant::fromValue(QDBusVariant(positionUs)));

    if (!reply.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Seek command failed:"
                   << reply.error().message();
    } else {
        position_ = positionMs;
        emit positionChanged();
        qDebug() << "[BluetoothAudioPlayer] Seek to:" << positionMs << "ms";
    }
}

void BluetoothAudioPlayer::updatePosition()
{
    if (!playing_ || !mediaPlayerInterface_ || !mediaPlayerInterface_->isValid()) {
        return;
    }

    // Query current position from MediaPlayer
    QVariant posVar = mediaPlayerInterface_->property("Position");
    if (posVar.isValid()) {
        position_ = posVar.toUInt();
        emit positionChanged();
    }
}

void BluetoothAudioPlayer::disconnectDevice()
{
    setConnectedDevice(QString());
}

void BluetoothAudioPlayer::onBlueZServiceOwnerChanged(
    const QString& service,
    const QString& oldOwner,
    const QString& newOwner)
{
    Q_UNUSED(service)
    Q_UNUSED(oldOwner)

    if (newOwner.isEmpty()) {
        // BlueZ service stopped
        qWarning() << "[BluetoothAudioPlayer] BlueZ service stopped";
        setConnectedDevice(QString());
    } else {
        // BlueZ service started
        qDebug() << "[BluetoothAudioPlayer] BlueZ service started";
        if (!devicePath_.isEmpty()) {
            QTimer::singleShot(1000, this, &BluetoothAudioPlayer::discoverMediaPlayer);
        }
    }
}

QString BluetoothAudioPlayer::extractDeviceName(const QString& devicePath)
{
    QDBusInterface device("org.bluez", devicePath, "org.bluez.Device1",
                         QDBusConnection::systemBus());

    if (!device.isValid()) {
        qWarning() << "[BluetoothAudioPlayer] Invalid device interface for:" << devicePath;
        return "Unknown Device";
    }

    QVariant nameVar = device.property("Name");
    if (nameVar.isValid()) {
        return nameVar.toString();
    }

    return "Unknown Device";
}

void BluetoothAudioPlayer::resetState()
{
    playing_ = false;
    status_ = "stopped";
    trackTitle_ = "No Track";
    trackArtist_ = "Unknown Artist";
    trackAlbum_ = "Unknown Album";
    duration_ = 0;
    position_ = 0;
    hasAlbumArt_ = false;
    albumArtPath_.clear();
    mediaPlayerPath_.clear();
    volume_ = 50;

    emit playingChanged();
    emit statusChanged();
    emit trackTitleChanged();
    emit trackArtistChanged();
    emit trackAlbumChanged();
    emit durationChanged();
    emit positionChanged();
    emit albumArtChanged();
    emit volumeChanged();
}

// ========== PulseAudio Local Volume Control ==========

QString BluetoothAudioPlayer::getPulseAudioSourceName() const
{
    if (devicePath_.isEmpty()) {
        return QString();
    }

    // Extract MAC address from device path: /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX
    QString macAddress = devicePath_;
    macAddress.remove("/org/bluez/hci0/dev_");

    // PulseAudio source name format: bluez_source.XX_XX_XX_XX_XX_XX.a2dp_source
    return QString("bluez_source.%1.a2dp_source").arg(macAddress);
}

void BluetoothAudioPlayer::setPulseAudioVolume(int percent)
{
    QString sourceName = getPulseAudioSourceName();
    if (sourceName.isEmpty()) {
        qWarning() << "[BluetoothAudioPlayer] Cannot set PulseAudio volume: no source name";
        return;
    }

    // pactl set-source-volume <source> <volume>%
    QProcess process;
    QStringList args;
    args << "set-source-volume" << sourceName << QString("%1%").arg(percent);

    process.start("pactl", args);
    if (!process.waitForFinished(2000)) {
        qWarning() << "[BluetoothAudioPlayer] pactl set-source-volume timeout";
        return;
    }

    if (process.exitCode() == 0) {
        qDebug() << "[BluetoothAudioPlayer] Set PulseAudio volume to" << percent << "% for" << sourceName;
    } else {
        QString errorOutput = process.readAllStandardError();
        qWarning() << "[BluetoothAudioPlayer] pactl set-source-volume failed:" << errorOutput;
    }
}

int BluetoothAudioPlayer::getPulseAudioVolume()
{
    QString sourceName = getPulseAudioSourceName();
    if (sourceName.isEmpty()) {
        qWarning() << "[BluetoothAudioPlayer] Cannot get PulseAudio volume: no source name";
        return -1;
    }

    // pactl list sources | grep -A 10 <source> | grep "Volume:"
    QProcess process;
    QStringList args;
    args << "list" << "sources";

    process.start("pactl", args);
    if (!process.waitForFinished(2000)) {
        qWarning() << "[BluetoothAudioPlayer] pactl list sources timeout";
        return -1;
    }

    if (process.exitCode() != 0) {
        QString errorOutput = process.readAllStandardError();
        qWarning() << "[BluetoothAudioPlayer] pactl list sources failed:" << errorOutput;
        return -1;
    }

    QString output = process.readAllStandardOutput();
    QStringList lines = output.split('\n');

    // Find the source block and extract volume
    bool foundSource = false;
    for (const QString& line : lines) {
        if (line.contains("Name:") && line.contains(sourceName)) {
            foundSource = true;
            continue;
        }

        if (foundSource && line.contains("Volume:")) {
            // Parse: "Volume: front-left: 19609 /  30% / -31.44 dB"
            QRegularExpression re(R"((\d+)%)");
            QRegularExpressionMatch match = re.match(line);
            if (match.hasMatch()) {
                int volume = match.captured(1).toInt();
                qDebug() << "[BluetoothAudioPlayer] Read PulseAudio volume:" << volume << "% from" << sourceName;
                return volume;
            }
            break;
        }

        // Stop searching after this source's block
        if (foundSource && line.startsWith("Source #")) {
            break;
        }
    }

    qWarning() << "[BluetoothAudioPlayer] Could not parse volume from pactl output";
    return -1;
}
