#include "backend/ota/ota_status_client.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QDBusConnection>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QtGlobal>
#include <initializer_list>

namespace {
constexpr int kMinPollIntervalMs = 3000;
constexpr int kMaxPollIntervalMs = 60000;

constexpr int kMinTimeoutMs = 1000;
constexpr int kMaxTimeoutMs = 15000;

constexpr int kMaxRetryAttempts = 3;
constexpr int kRetryBaseDelayMs = 1000;

const QString kOtaDbusPath = QStringLiteral("/com/des/ota/Status");
const QString kOtaDbusInterface = QStringLiteral("com.des.ota.Status1");
const QString kOtaDbusSignalUpdateAvailability = QStringLiteral("UpdateAvailabilityChanged");

QString jsonValueToCompactString(const QJsonValue& value) {
    if (value.isNull() || value.isUndefined()) {
        return QString();
    }
    if (value.isObject()) {
        return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact));
    }
    if (value.isArray()) {
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact));
    }
    if (value.isBool()) {
        return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    }
    if (value.isDouble()) {
        return QString::number(value.toDouble(), 'g', 15);
    }
    return QString();
}

QString toStringOrEmpty(const QJsonValue& value) {
    if (value.isString()) {
        return value.toString().trimmed();
    }
    if (value.isDouble() || value.isBool()) {
        return jsonValueToCompactString(value);
    }
    return QString();
}

bool toBoolOrDefault(const QJsonValue& value, bool fallback = false) {
    if (value.isBool()) {
        return value.toBool();
    }
    if (value.isDouble()) {
        return !qFuzzyIsNull(value.toDouble());
    }
    if (value.isString()) {
        const QString normalized = value.toString().trimmed().toLower();
        if (normalized == QStringLiteral("1")
            || normalized == QStringLiteral("true")
            || normalized == QStringLiteral("yes")
            || normalized == QStringLiteral("y")
            || normalized == QStringLiteral("on")) {
            return true;
        }
        if (normalized == QStringLiteral("0")
            || normalized == QStringLiteral("false")
            || normalized == QStringLiteral("no")
            || normalized == QStringLiteral("n")
            || normalized == QStringLiteral("off")) {
            return false;
        }
    }
    return fallback;
}

QJsonValue valueAtPath(const QJsonObject& root, const QString& dottedPath) {
    if (dottedPath.isEmpty()) {
        return QJsonValue();
    }

    QJsonValue cursor(root);
    const QStringList tokens = dottedPath.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    for (const QString& token : tokens) {
        if (!cursor.isObject()) {
            return QJsonValue();
        }
        const QJsonObject object = cursor.toObject();
        const auto it = object.constFind(token);
        if (it == object.constEnd()) {
            return QJsonValue();
        }
        cursor = it.value();
    }
    return cursor;
}

QJsonValue firstExistingValue(const QJsonObject& root, std::initializer_list<const char*> paths) {
    for (const char* rawPath : paths) {
        if (!rawPath || !rawPath[0]) {
            continue;
        }
        const QJsonValue value = valueAtPath(root, QString::fromLatin1(rawPath));
        if (!value.isUndefined() && !value.isNull()) {
            return value;
        }
    }
    return QJsonValue();
}

QString firstNonEmptyString(const QJsonObject& root, std::initializer_list<const char*> paths) {
    for (const char* rawPath : paths) {
        if (!rawPath || !rawPath[0]) {
            continue;
        }
        const QString value = toStringOrEmpty(valueAtPath(root, QString::fromLatin1(rawPath)));
        if (!value.isEmpty()) {
            return value;
        }
    }
    return QString();
}

QDateTime parseTimestamp(const QString& rawText) {
    const QString text = rawText.trimmed();
    if (text.isEmpty()) {
        return QDateTime();
    }

    QDateTime parsed = QDateTime::fromString(text, Qt::ISODateWithMs);
    if (!parsed.isValid()) {
        parsed = QDateTime::fromString(text, Qt::ISODate);
    }
    if (!parsed.isValid()) {
        parsed = QDateTime::fromString(text, QStringLiteral("yyyy-MM-dd hh:mm:ss"));
    }
    return parsed;
}

QStringList toStringList(const QJsonValue& value) {
    QStringList list;
    if (value.isString()) {
        const QString single = value.toString().trimmed();
        if (!single.isEmpty()) {
            list.push_back(single);
        }
        return list;
    }

    if (!value.isArray()) {
        return list;
    }

    const QJsonArray arr = value.toArray();
    list.reserve(arr.size());
    for (const QJsonValue& entry : arr) {
        if (entry.isString()) {
            list.push_back(entry.toString());
        } else if (!entry.isNull() && !entry.isUndefined()) {
            const QString compact = jsonValueToCompactString(entry);
            if (!compact.isEmpty()) {
                list.push_back(compact);
            }
        }
    }
    return list;
}

QVariantList toSlotList(const QJsonValue& value) {
    QVariantList slotItems;
    if (value.isObject()) {
        const QJsonObject slotObject = value.toObject();
        slotItems.reserve(slotObject.size());

        for (auto it = slotObject.constBegin(); it != slotObject.constEnd(); ++it) {
            if (!it.value().isObject()) {
                continue;
            }
            QVariantMap slotMap = it.value().toObject().toVariantMap();
            if (!slotMap.contains(QStringLiteral("name"))
                || slotMap.value(QStringLiteral("name")).toString().trimmed().isEmpty()) {
                slotMap.insert(QStringLiteral("name"), it.key());
            }
            slotItems.push_back(slotMap);
        }
        return slotItems;
    }

    if (!value.isArray()) {
        return slotItems;
    }

    const QJsonArray arr = value.toArray();
    slotItems.reserve(arr.size());
    for (const QJsonValue& entry : arr) {
        if (entry.isObject()) {
            slotItems.push_back(entry.toObject().toVariantMap());
        }
    }
    return slotItems;
}

template <typename T>
bool assignIfChanged(T& dst, const T& src) {
    if (dst == src) {
        return false;
    }
    dst = src;
    return true;
}
} // namespace

OtaStatusClient::OtaStatusClient(QObject* parent)
    : QObject(parent)
    , networkManager_(new QNetworkAccessManager(this))
    , pollTimer_(new QTimer(this))
    , requestTimeoutTimer_(new QTimer(this)) {

    pollTimer_->setSingleShot(true);
    connect(pollTimer_, &QTimer::timeout, this, &OtaStatusClient::onPollTimerTimeout);

    requestTimeoutTimer_->setSingleShot(true);
    connect(requestTimeoutTimer_, &QTimer::timeout, this, &OtaStatusClient::onRequestTimeout);

    QDBusConnection::systemBus().connect(
        QString(),
        kOtaDbusPath,
        kOtaDbusInterface,
        kOtaDbusSignalUpdateAvailability,
        this,
        SLOT(onUpdateAvailabilityChanged(bool,QString,QString,QString)));
}

OtaStatusClient::~OtaStatusClient() {
    stopPolling();
}

QString OtaStatusClient::baseUrl() const {
    return baseUrl_;
}

void OtaStatusClient::setBaseUrl(const QString& baseUrl) {
    const QString normalized = normalizeBaseUrl(baseUrl);
    if (!assignIfChanged(baseUrl_, normalized)) {
        return;
    }

    emit baseUrlChanged();
}

int OtaStatusClient::pollIntervalMs() const {
    return pollIntervalMs_;
}

void OtaStatusClient::setPollIntervalMs(int intervalMs) {
    const int clamped = qBound(kMinPollIntervalMs, intervalMs, kMaxPollIntervalMs);
    if (!assignIfChanged(pollIntervalMs_, clamped)) {
        return;
    }

    emit pollIntervalMsChanged();
}

int OtaStatusClient::timeoutMs() const {
    return timeoutMs_;
}

void OtaStatusClient::setTimeoutMs(int timeoutMs) {
    const int clamped = qBound(kMinTimeoutMs, timeoutMs, kMaxTimeoutMs);
    if (!assignIfChanged(timeoutMs_, clamped)) {
        return;
    }

    emit timeoutMsChanged();
}

bool OtaStatusClient::polling() const {
    return polling_;
}

bool OtaStatusClient::requestInFlight() const {
    return requestInFlight_;
}

bool OtaStatusClient::online() const {
    return online_;
}

int OtaStatusClient::retryCount() const {
    return retryCount_;
}

QString OtaStatusClient::requestError() const {
    return requestError_;
}

QString OtaStatusClient::backendError() const {
    return backendError_;
}

QDateTime OtaStatusClient::lastUpdated() const {
    return lastUpdated_;
}

QString OtaStatusClient::deviceId() const {
    return deviceId_;
}

QString OtaStatusClient::deviceModel() const {
    return deviceModel_;
}

QString OtaStatusClient::compatible() const {
    return compatible_;
}

QString OtaStatusClient::currentSlot() const {
    return currentSlot_;
}

QString OtaStatusClient::currentVersion() const {
    return currentVersion_;
}

QString OtaStatusClient::targetVersion() const {
    return targetVersion_;
}

bool OtaStatusClient::updateAvailable() const {
    return updateAvailable_;
}

QString OtaStatusClient::availableReleaseId() const {
    return availableReleaseId_;
}

QString OtaStatusClient::availableVersion() const {
    return availableVersion_;
}

QDateTime OtaStatusClient::availableAnnounceTs() const {
    return availableAnnounceTs_;
}

QString OtaStatusClient::otaId() const {
    return otaId_;
}

QString OtaStatusClient::ipAddress() const {
    return ipAddress_;
}

QString OtaStatusClient::ipSource() const {
    return ipSource_;
}

QStringList OtaStatusClient::otaLog() const {
    return otaLog_;
}

QVariantList OtaStatusClient::slotList() const {
    return slots_;
}

OtaStatusClient::Phase OtaStatusClient::phase() const {
    return phase_;
}

OtaStatusClient::Event OtaStatusClient::event() const {
    return event_;
}

OtaStatusClient::OtaState OtaStatusClient::otaState() const {
    return otaState_;
}

QString OtaStatusClient::phaseText() const {
    switch (phase_) {
    case Phase::Idle:
        return QStringLiteral("IDLE");
    case Phase::Download:
        return QStringLiteral("DOWNLOAD");
    case Phase::Apply:
        return QStringLiteral("APPLY");
    case Phase::Reboot:
        return QStringLiteral("REBOOT");
    case Phase::Commit:
        return QStringLiteral("COMMIT");
    case Phase::Unknown:
    default:
        return QStringLiteral("UNKNOWN");
    }
}

QString OtaStatusClient::eventText() const {
    switch (event_) {
    case Event::None:
        return QStringLiteral("NONE");
    case Event::Start:
        return QStringLiteral("START");
    case Event::Ok:
        return QStringLiteral("OK");
    case Event::Fail:
        return QStringLiteral("FAIL");
    case Event::Unknown:
    default:
        return QStringLiteral("UNKNOWN");
    }
}

void OtaStatusClient::startPolling() {
    if (polling_) {
        return;
    }

    polling_ = true;
    emit pollingChanged();
    scheduleNextPoll(0);
}

void OtaStatusClient::stopPolling() {
    if (pollTimer_) {
        pollTimer_->stop();
    }
    if (requestTimeoutTimer_) {
        requestTimeoutTimer_->stop();
    }

    if (pendingReply_) {
        pendingReply_->abort();
        pendingReply_.clear();
    }
    pendingRequestKind_ = RequestKind::None;
    requestTimedOut_ = false;

    if (requestInFlight_) {
        requestInFlight_ = false;
        emit requestInFlightChanged();
    }

    setRetryCount(0);
    setRequestError(QString());

    if (!polling_) {
        return;
    }

    polling_ = false;
    emit pollingChanged();
}

void OtaStatusClient::refreshNow() {
    if (requestInFlight_) {
        return;
    }
    fetchStatusInternal();
}

void OtaStatusClient::requestUpdate() {
    if (requestInFlight_ || !networkManager_) {
        return;
    }

    if (pollTimer_) {
        // Avoid losing periodic polling when update request overlaps with poll timeout.
        pollTimer_->stop();
    }

    const QUrl endpoint(normalizeBaseUrl(baseUrl_) + QStringLiteral("/ota/request-update"));
    QNetworkRequest request(endpoint);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QJsonObject body;
    if (!availableReleaseId_.isEmpty()) {
        body.insert(QStringLiteral("release_id"), availableReleaseId_);
    }
    if (!availableVersion_.isEmpty()) {
        body.insert(QStringLiteral("version"), availableVersion_);
    }
    if (!deviceId_.isEmpty()) {
        body.insert(QStringLiteral("device_id"), deviceId_);
    }
    if (!ipAddress_.isEmpty() && ipAddress_ != QStringLiteral("-")) {
        body.insert(QStringLiteral("ip"), ipAddress_);
    }

    pendingReply_ = networkManager_->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    pendingRequestKind_ = RequestKind::UpdateRequest;
    requestTimedOut_ = false;

    requestInFlight_ = true;
    emit requestInFlightChanged();

    connect(pendingReply_, &QNetworkReply::finished, this, &OtaStatusClient::onRequestFinished);
    if (requestTimeoutTimer_) {
        requestTimeoutTimer_->start(timeoutMs_);
    }
}

void OtaStatusClient::onPollTimerTimeout() {
    if (requestInFlight_) {
        scheduleNextPoll(500);
        return;
    }
    fetchStatusInternal();
}

void OtaStatusClient::onRequestTimeout() {
    if (!pendingReply_) {
        return;
    }

    requestTimedOut_ = true;
    pendingReply_->abort();
}

void OtaStatusClient::onRequestFinished() {
    QNetworkReply* reply = pendingReply_.data();
    if (!reply) {
        return;
    }

    const RequestKind finishedRequestKind = pendingRequestKind_;
    pendingRequestKind_ = RequestKind::None;
    pendingReply_.clear();

    if (requestTimeoutTimer_) {
        requestTimeoutTimer_->stop();
    }

    if (requestInFlight_) {
        requestInFlight_ = false;
        emit requestInFlightChanged();
    }

    const bool timedOut = requestTimedOut_;
    requestTimedOut_ = false;

    if (reply->error() != QNetworkReply::NoError) {
        const QString errorText = timedOut
            ? tr("Request timeout after %1 ms").arg(timeoutMs_)
            : reply->errorString();

        reply->deleteLater();
        if (finishedRequestKind == RequestKind::UpdateRequest) {
            handleUpdateRequestFailure(errorText);
            if (polling_) {
                scheduleNextPoll(0);
            }
        } else {
            handleStatusFailure(errorText);
        }
        return;
    }

    const QByteArray response = reply->readAll();
    reply->deleteLater();

    QJsonParseError parseError{};
    const QJsonDocument doc = QJsonDocument::fromJson(response, &parseError);

    if (finishedRequestKind == RequestKind::UpdateRequest) {
        if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
            const QJsonObject payload = doc.object();
            const QJsonValue okValue = payload.value(QStringLiteral("ok"));
            const bool ok = okValue.isUndefined() ? true : toBoolOrDefault(okValue, false);
            if (!ok) {
                QString errorText = firstNonEmptyString(payload, {"detail", "message"});
                if (errorText.isEmpty()) {
                    errorText = tr("Update request rejected");
                }
                handleUpdateRequestFailure(errorText);
                if (polling_) {
                    scheduleNextPoll(0);
                }
                return;
            }
        } else if (!response.trimmed().isEmpty()) {
            handleUpdateRequestFailure(tr("Invalid JSON payload from /ota/request-update"));
            if (polling_) {
                scheduleNextPoll(0);
            }
            return;
        }

        setRequestError(QString());
        emit statusUpdated();
        if (polling_) {
            scheduleNextPoll(0);
        }
        return;
    }

    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        handleStatusFailure(tr("Invalid JSON payload from /ota/status"));
        return;
    }

    updateFromPayload(doc.object());
    setOnline(true);
    setRetryCount(0);
    setRequestError(QString());
    emit statusUpdated();
    scheduleNextPoll(pollIntervalMs_);
}

void OtaStatusClient::onUpdateAvailabilityChanged(
    bool updateAvailable,
    const QString& releaseId,
    const QString& version,
    const QString& announceTs) {
    const QString nextReleaseId = releaseId.trimmed();
    const QString nextVersion = version.trimmed();
    const QString nextAnnounceText = announceTs.trimmed();

    if (assignIfChanged(updateAvailable_, updateAvailable)) {
        emit updateAvailableChanged();
    }
    if (assignIfChanged(availableReleaseId_, nextReleaseId)) {
        emit availableReleaseIdChanged();
    }
    if (assignIfChanged(availableVersion_, nextVersion)) {
        emit availableVersionChanged();
    }

    QDateTime nextAnnounceTs;
    if (!nextAnnounceText.isEmpty()) {
        nextAnnounceTs = parseTimestamp(nextAnnounceText);
    }
    if (updateAvailable && !nextAnnounceTs.isValid()) {
        nextAnnounceTs = QDateTime::currentDateTime();
    }
    if (assignIfChanged(availableAnnounceTs_, nextAnnounceTs)) {
        emit availableAnnounceTsChanged();
    }

    const QDateTime now = QDateTime::currentDateTime();
    if (assignIfChanged(lastUpdated_, now)) {
        emit lastUpdatedChanged();
    }

    setOnline(true);
    emit statusUpdated();
}

QString OtaStatusClient::normalizeBaseUrl(const QString& baseUrl) {
    QString normalized = baseUrl.trimmed();
    if (normalized.isEmpty()) {
        normalized = QStringLiteral("http://127.0.0.1:8080");
    } else if (!normalized.startsWith(QStringLiteral("http://"))
               && !normalized.startsWith(QStringLiteral("https://"))) {
        normalized.prepend(QStringLiteral("http://"));
    }

    while (normalized.endsWith(QLatin1Char('/'))) {
        normalized.chop(1);
    }

    return normalized;
}

OtaStatusClient::Phase OtaStatusClient::phaseFromString(const QString& phaseText) {
    const QString normalized = phaseText.trimmed().toUpper();
    if (normalized.isEmpty() || normalized == QStringLiteral("-")
        || normalized == QStringLiteral("NONE")
        || normalized == QStringLiteral("IDLE")
        || normalized == QStringLiteral("READY")) {
        return Phase::Idle;
    }
    if (normalized == QStringLiteral("DOWNLOAD") || normalized == QStringLiteral("DOWNLOADING")) {
        return Phase::Download;
    }
    if (normalized == QStringLiteral("APPLY") || normalized == QStringLiteral("APPLYING")
        || normalized == QStringLiteral("INSTALL") || normalized == QStringLiteral("INSTALLING")
        || normalized == QStringLiteral("VERIFY") || normalized == QStringLiteral("VERIFICATION")) {
        return Phase::Apply;
    }
    if (normalized == QStringLiteral("REBOOT") || normalized == QStringLiteral("RESTART")) {
        return Phase::Reboot;
    }
    if (normalized == QStringLiteral("COMMIT") || normalized == QStringLiteral("MARK_GOOD")) {
        return Phase::Commit;
    }
    return Phase::Unknown;
}

OtaStatusClient::Event OtaStatusClient::eventFromString(const QString& eventText) {
    const QString normalized = eventText.trimmed().toUpper();
    if (normalized.isEmpty() || normalized == QStringLiteral("-")
        || normalized == QStringLiteral("NONE")
        || normalized == QStringLiteral("IDLE")) {
        return Event::None;
    }
    if (normalized == QStringLiteral("START")
        || normalized == QStringLiteral("RUNNING")
        || normalized == QStringLiteral("IN_PROGRESS")) {
        return Event::Start;
    }
    if (normalized == QStringLiteral("OK")
        || normalized == QStringLiteral("SUCCESS")
        || normalized == QStringLiteral("COMPLETED")
        || normalized == QStringLiteral("DONE")
        || normalized == QStringLiteral("PASS")) {
        return Event::Ok;
    }
    if (normalized == QStringLiteral("FAIL")
        || normalized == QStringLiteral("FAILED")
        || normalized == QStringLiteral("ERROR")
        || normalized == QStringLiteral("ERR")) {
        return Event::Fail;
    }
    return Event::Unknown;
}

OtaStatusClient::OtaState OtaStatusClient::stateFrom(Phase phase, Event event, bool online) {
    if (!online) {
        return OtaState::Offline;
    }
    if (event == Event::Fail) {
        return OtaState::Failed;
    }
    if (phase == Phase::Download || phase == Phase::Apply || phase == Phase::Reboot || phase == Phase::Commit) {
        return OtaState::Running;
    }
    if (event == Event::Ok) {
        return OtaState::Success;
    }
    return OtaState::Idle;
}

void OtaStatusClient::scheduleNextPoll(int delayMs) {
    if (!polling_ || !pollTimer_) {
        return;
    }
    pollTimer_->start(qMax(0, delayMs));
}

void OtaStatusClient::fetchStatusInternal() {
    if (requestInFlight_ || !networkManager_) {
        return;
    }

    const QUrl endpoint(normalizeBaseUrl(baseUrl_) + QStringLiteral("/ota/status"));
    QNetworkRequest request(endpoint);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    pendingReply_ = networkManager_->get(request);
    pendingRequestKind_ = RequestKind::StatusPoll;
    requestTimedOut_ = false;

    requestInFlight_ = true;
    emit requestInFlightChanged();

    connect(pendingReply_, &QNetworkReply::finished, this, &OtaStatusClient::onRequestFinished);
    if (requestTimeoutTimer_) {
        requestTimeoutTimer_->start(timeoutMs_);
    }
}

void OtaStatusClient::handleStatusFailure(const QString& errorText) {
    setOnline(false);
    setRequestError(errorText);

    const int nextRetry = qMin(retryCount_ + 1, kMaxRetryAttempts);
    setRetryCount(nextRetry);

    emit requestFailed(errorText);

    const int retryDelayMs = qMin(kRetryBaseDelayMs * qMax(1, retryCount_), pollIntervalMs_);
    scheduleNextPoll(retryDelayMs);
}

void OtaStatusClient::handleUpdateRequestFailure(const QString& errorText) {
    setRequestError(errorText);
    emit requestFailed(errorText);
}

void OtaStatusClient::updateFromPayload(const QJsonObject& payload) {
    const QString nextDeviceId = firstNonEmptyString(
        payload,
        {"device_id", "device.device_id", "device.id"});
    if (assignIfChanged(deviceId_, nextDeviceId)) {
        emit deviceIdChanged();
    }

    const QString nextDeviceModel = firstNonEmptyString(
        payload,
        {"device_model", "device.model", "compatible", "device.compatible"});
    if (assignIfChanged(deviceModel_, nextDeviceModel)) {
        emit deviceModelChanged();
    }

    const QString nextCompatible = firstNonEmptyString(payload, {"compatible", "device.compatible"});
    if (assignIfChanged(compatible_, nextCompatible)) {
        emit compatibleChanged();
    }

    const QString nextCurrentSlot = firstNonEmptyString(
        payload,
        {"current_slot", "device.current_slot", "log_vehicle.current_slot"});
    if (assignIfChanged(currentSlot_, nextCurrentSlot)) {
        emit currentSlotChanged();
    }

    const QString nextCurrentVersion = firstNonEmptyString(
        payload,
        {"current_version", "ota.current_version"});
    if (assignIfChanged(currentVersion_, nextCurrentVersion)) {
        emit currentVersionChanged();
    }

    const QString nextTargetVersion = firstNonEmptyString(
        payload,
        {"target_version", "ota.target_version"});
    if (assignIfChanged(targetVersion_, nextTargetVersion)) {
        emit targetVersionChanged();
    }

    const bool nextUpdateAvailable = toBoolOrDefault(
        firstExistingValue(payload, {"update_available", "ota.update_available"}),
        false);
    if (assignIfChanged(updateAvailable_, nextUpdateAvailable)) {
        emit updateAvailableChanged();
    }

    const QString nextAvailableReleaseId = firstNonEmptyString(
        payload,
        {"available_release_id", "ota.available_release_id"});
    if (assignIfChanged(availableReleaseId_, nextAvailableReleaseId)) {
        emit availableReleaseIdChanged();
    }

    const QString nextAvailableVersion = firstNonEmptyString(
        payload,
        {"available_version", "ota.available_version"});
    if (assignIfChanged(availableVersion_, nextAvailableVersion)) {
        emit availableVersionChanged();
    }

    const QDateTime nextAvailableAnnounceTs = parseTimestamp(
        firstNonEmptyString(payload, {"available_announce_ts", "ota.available_announce_ts"}));
    if (assignIfChanged(availableAnnounceTs_, nextAvailableAnnounceTs)) {
        emit availableAnnounceTsChanged();
    }

    const QString nextOtaId = firstNonEmptyString(payload, {"ota_id", "ota.ota_id"});
    if (assignIfChanged(otaId_, nextOtaId)) {
        emit otaIdChanged();
    }

    const QString resolvedIp = firstNonEmptyString(
        payload,
        {"ip_address", "ip", "context.network.ip", "network.ip"});
    if (assignIfChanged(ipAddress_, resolvedIp)) {
        emit ipAddressChanged();
    }

    const QString nextIpSource = firstNonEmptyString(
        payload,
        {"ip_source", "context.network.ip_source", "network.ip_source"});
    if (assignIfChanged(ipSource_, nextIpSource)) {
        emit ipSourceChanged();
    }

    const QString nextBackendError = firstNonEmptyString(
        payload,
        {"last_error", "error.code", "error.message", "error"});
    if (assignIfChanged(backendError_, nextBackendError)) {
        emit backendErrorChanged();
    }

    const QStringList newLog = toStringList(
        firstExistingValue(payload, {"ota_log", "evidence.ota_log", "ota.ota_log"}));
    if (assignIfChanged(otaLog_, newLog)) {
        emit otaLogChanged();
    }

    const QVariantList newSlots = toSlotList(firstExistingValue(payload, {"slots", "device.slots"}));
    if (assignIfChanged(slots_, newSlots)) {
        emit slotsChanged();
    }

    const Phase nextPhase = phaseFromString(firstNonEmptyString(payload, {"phase", "ota.phase"}));
    if (assignIfChanged(phase_, nextPhase)) {
        emit phaseChanged();
    }

    const Event nextEvent = eventFromString(firstNonEmptyString(payload, {"event", "ota.event"}));
    if (assignIfChanged(event_, nextEvent)) {
        emit eventChanged();
    }

    const QString timestampText = firstNonEmptyString(
        payload,
        {"ts", "context.time.local", "time.local", "timestamp"});
    QDateTime parsedTimestamp = parseTimestamp(timestampText);
    if (!parsedTimestamp.isValid()) {
        parsedTimestamp = QDateTime::currentDateTime();
    }
    if (assignIfChanged(lastUpdated_, parsedTimestamp)) {
        emit lastUpdatedChanged();
    }

    const OtaState nextState = stateFrom(phase_, event_, true);
    if (assignIfChanged(otaState_, nextState)) {
        emit otaStateChanged();
    }
}

bool OtaStatusClient::setOnline(bool online) {
    if (!assignIfChanged(online_, online)) {
        return false;
    }

    emit onlineChanged();

    const OtaState nextState = stateFrom(phase_, event_, online_);
    if (assignIfChanged(otaState_, nextState)) {
        emit otaStateChanged();
    }
    return true;
}

bool OtaStatusClient::setRetryCount(int retryCount) {
    if (!assignIfChanged(retryCount_, retryCount)) {
        return false;
    }
    emit retryCountChanged();
    return true;
}

bool OtaStatusClient::setRequestError(const QString& requestError) {
    if (!assignIfChanged(requestError_, requestError)) {
        return false;
    }
    emit requestErrorChanged();
    return true;
}
