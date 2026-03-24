#ifndef BACKEND_OTA_OTA_STATUS_CLIENT_H
#define BACKEND_OTA_OTA_STATUS_CLIENT_H

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QVariantList>

class QJsonObject;
class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

class OtaStatusClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)
    Q_PROPERTY(int pollIntervalMs READ pollIntervalMs WRITE setPollIntervalMs NOTIFY pollIntervalMsChanged)
    Q_PROPERTY(int timeoutMs READ timeoutMs WRITE setTimeoutMs NOTIFY timeoutMsChanged)
    Q_PROPERTY(bool polling READ polling NOTIFY pollingChanged)
    Q_PROPERTY(bool requestInFlight READ requestInFlight NOTIFY requestInFlightChanged)
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    Q_PROPERTY(int retryCount READ retryCount NOTIFY retryCountChanged)
    Q_PROPERTY(QString requestError READ requestError NOTIFY requestErrorChanged)
    Q_PROPERTY(QString backendError READ backendError NOTIFY backendErrorChanged)
    Q_PROPERTY(QDateTime lastUpdated READ lastUpdated NOTIFY lastUpdatedChanged)
    Q_PROPERTY(QString deviceId READ deviceId NOTIFY deviceIdChanged)
    Q_PROPERTY(QString deviceModel READ deviceModel NOTIFY deviceModelChanged)
    Q_PROPERTY(QString compatible READ compatible NOTIFY compatibleChanged)
    Q_PROPERTY(QString currentSlot READ currentSlot NOTIFY currentSlotChanged)
    Q_PROPERTY(QString currentVersion READ currentVersion NOTIFY currentVersionChanged)
    Q_PROPERTY(QString targetVersion READ targetVersion NOTIFY targetVersionChanged)
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY updateAvailableChanged)
    Q_PROPERTY(QString availableReleaseId READ availableReleaseId NOTIFY availableReleaseIdChanged)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY availableVersionChanged)
    Q_PROPERTY(QDateTime availableAnnounceTs READ availableAnnounceTs NOTIFY availableAnnounceTsChanged)
    Q_PROPERTY(QString otaId READ otaId NOTIFY otaIdChanged)
    Q_PROPERTY(QString ipAddress READ ipAddress NOTIFY ipAddressChanged)
    Q_PROPERTY(QString ipSource READ ipSource NOTIFY ipSourceChanged)
    Q_PROPERTY(QStringList otaLog READ otaLog NOTIFY otaLogChanged)
    Q_PROPERTY(QVariantList slots READ slotList NOTIFY slotsChanged)
    Q_PROPERTY(Phase phase READ phase NOTIFY phaseChanged)
    Q_PROPERTY(Event event READ event NOTIFY eventChanged)
    Q_PROPERTY(OtaState otaState READ otaState NOTIFY otaStateChanged)
    Q_PROPERTY(QString phaseText READ phaseText NOTIFY phaseChanged)
    Q_PROPERTY(QString eventText READ eventText NOTIFY eventChanged)

public:
    enum class Phase {
        Unknown = 0,
        Idle,
        Download,
        Apply,
        Reboot,
        Commit,
    };
    Q_ENUM(Phase)

    enum class Event {
        Unknown = 0,
        None,
        Start,
        Ok,
        Fail,
    };
    Q_ENUM(Event)

    enum class OtaState {
        Offline = 0,
        Idle,
        Running,
        Success,
        Failed,
    };
    Q_ENUM(OtaState)

    explicit OtaStatusClient(QObject* parent = nullptr);
    ~OtaStatusClient() override;

    QString baseUrl() const;
    void setBaseUrl(const QString& baseUrl);

    int pollIntervalMs() const;
    void setPollIntervalMs(int intervalMs);

    int timeoutMs() const;
    void setTimeoutMs(int timeoutMs);

    bool polling() const;
    bool requestInFlight() const;
    bool online() const;
    int retryCount() const;

    QString requestError() const;
    QString backendError() const;
    QDateTime lastUpdated() const;

    QString deviceId() const;
    QString deviceModel() const;
    QString compatible() const;
    QString currentSlot() const;
    QString currentVersion() const;
    QString targetVersion() const;
    bool updateAvailable() const;
    QString availableReleaseId() const;
    QString availableVersion() const;
    QDateTime availableAnnounceTs() const;
    QString otaId() const;
    QString ipAddress() const;
    QString ipSource() const;
    QStringList otaLog() const;
    QVariantList slotList() const;

    Phase phase() const;
    Event event() const;
    OtaState otaState() const;
    QString phaseText() const;
    QString eventText() const;

    Q_INVOKABLE void startPolling();
    Q_INVOKABLE void stopPolling();
    Q_INVOKABLE void refreshNow();
    Q_INVOKABLE void requestUpdate();

signals:
    void baseUrlChanged();
    void pollIntervalMsChanged();
    void timeoutMsChanged();
    void pollingChanged();
    void requestInFlightChanged();
    void onlineChanged();
    void retryCountChanged();
    void requestErrorChanged();
    void backendErrorChanged();
    void lastUpdatedChanged();
    void deviceIdChanged();
    void deviceModelChanged();
    void compatibleChanged();
    void currentSlotChanged();
    void currentVersionChanged();
    void targetVersionChanged();
    void updateAvailableChanged();
    void availableReleaseIdChanged();
    void availableVersionChanged();
    void availableAnnounceTsChanged();
    void otaIdChanged();
    void ipAddressChanged();
    void ipSourceChanged();
    void otaLogChanged();
    void slotsChanged();
    void phaseChanged();
    void eventChanged();
    void otaStateChanged();
    void statusUpdated();
    void requestFailed(const QString& errorMessage);

private slots:
    void onPollTimerTimeout();
    void onRequestTimeout();
    void onRequestFinished();

private:
    enum class RequestKind {
        None = 0,
        StatusPoll,
        UpdateRequest,
    };

    static QString normalizeBaseUrl(const QString& baseUrl);
    static Phase phaseFromString(const QString& phaseText);
    static Event eventFromString(const QString& eventText);
    static OtaState stateFrom(Phase phase, Event event, bool online);

    void scheduleNextPoll(int delayMs);
    void fetchStatusInternal();
    void handleStatusFailure(const QString& errorText);
    void handleUpdateRequestFailure(const QString& errorText);
    void updateFromPayload(const QJsonObject& payload);

    bool setOnline(bool online);
    bool setRetryCount(int retryCount);
    bool setRequestError(const QString& requestError);

    QNetworkAccessManager* networkManager_ = nullptr;
    QPointer<QNetworkReply> pendingReply_;
    RequestKind pendingRequestKind_ = RequestKind::None;
    QTimer* pollTimer_ = nullptr;
    QTimer* requestTimeoutTimer_ = nullptr;

    QString baseUrl_ = QStringLiteral("http://127.0.0.1:8080");
    int pollIntervalMs_ = 60000;
    int timeoutMs_ = 2500;

    bool polling_ = false;
    bool requestInFlight_ = false;
    bool online_ = false;
    int retryCount_ = 0;
    bool requestTimedOut_ = false;

    QString requestError_;
    QString backendError_;
    QDateTime lastUpdated_;
    QString deviceId_;
    QString deviceModel_;
    QString compatible_;
    QString currentSlot_;
    QString currentVersion_;
    QString targetVersion_;
    bool updateAvailable_ = false;
    QString availableReleaseId_;
    QString availableVersion_;
    QDateTime availableAnnounceTs_;
    QString otaId_;
    QString ipAddress_;
    QString ipSource_;
    QStringList otaLog_;
    QVariantList slots_;

    Phase phase_ = Phase::Unknown;
    Event event_ = Event::Unknown;
    OtaState otaState_ = OtaState::Offline;
};

#endif // BACKEND_OTA_OTA_STATUS_CLIENT_H
