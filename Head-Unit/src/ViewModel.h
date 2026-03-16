#ifndef VIEWMODEL_H
#define VIEWMODEL_H

#include <QObject>
#include <QString>

#include <string>
#include <unordered_map>

class ViewModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString driveMode READ driveMode NOTIFY driveModeChanged)
    Q_PROPERTY(int ambientLightLevel READ ambientLightLevel NOTIFY ambientLightLevelChanged)
    Q_PROPERTY(bool musicPlaying READ musicPlaying NOTIFY musicPlayingChanged)

public:
    enum class TimerId {
        DriveMode,
        AmbientLight,
        MusicPlayback,
    };

    explicit ViewModel(QObject* parent = nullptr);

    QString driveMode() const;
    int ambientLightLevel() const;
    bool musicPlaying() const;

public slots:
    void receiveTimeout(const std::string& timerName);

signals:
    void driveModeChanged();
    void ambientLightLevelChanged();
    void musicPlayingChanged();

private:
    void handleDriveModeTick();
    void handleAmbientLightTick();
    void handleMusicTick();

    QString driveMode_ = QStringLiteral("NEUTRAL");
    int ambientLightLevel_ = 0;
    bool musicPlaying_ = false;
};

#endif // VIEWMODEL_H
