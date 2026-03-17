#include "backend/gear/gear_client.h"

#include <QDBusConnection>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher> 
#include <QDBusPendingReply>  
#include <QDBusReply>
#include <QDBusError>
#include <QVariant>
#include <QDebug>
#include <QString>
#include <QtCore/qglobal.h>

namespace {
// DBus constants with modern C++ 'constexpr'
constexpr auto ServiceName = "com.des.vehicle"; //service name on the bus uses dot
constexpr auto ObjectPath = "/com/des/vehicle/Gear"; //object path uses slash way
constexpr auto InterfaceName = "com.des.vehicle.Gear"; //interface name uses dot

constexpr const char* DefaultSource = "HeadUnit"; //default identifier for requests

constexpr quint8 GearNeutral = 0; //integer = 4bytes, quint8 = 1byte and unsigned -> memory efficient
constexpr quint8 GearDrive = 1; //I can use letter 'k' for coding convention
constexpr quint8 GearReverse = 2;
constexpr quint8 GearPark = 3;

constexpr const char* UseSessionEnv = "DES_GEAR_USE_SESSION_BUS"; //what is environment variable?

QDBusConnection gearBus() { //function to get DBus connection what is type QDBusConnection? 
    if (qEnvironmentVariableIsSet(UseSessionEnv)) { //I don't know which module has this function
        return QDBusConnection::sessionBus(); //if there's many sessionBus how can function sessionBus know which one to use? ass through if phrase?
    }
    return QDBusConnection::systemBus();
}

QString gearBusLabel() {
    return qEnvironmentVariableIsSet(UseSessionEnv)
               ? QStringLiteral("session")
               : QStringLiteral("system");
}
} // namespace

GearClient::GearClient(QObject* parent)
    : QObject(parent)
    , iface_(QString::fromLatin1(ServiceName),
             QString::fromLatin1(ObjectPath),
             QString::fromLatin1(InterfaceName),
             gearBus())
    , currentGear_(QStringLiteral("N"))
    , sequence_(0)
    , signalsConnected_(false) {

    if (!iface_.isValid()) {
        qWarning() << "[GearClient] DBus interface invalid on" << gearBusLabel() << "bus:"
                   << gearBus().lastError().message();
    }

    subscribeToSignals();
    fetchInitialGear();
}

QString GearClient::currentGear() const {
    return currentGear_;
}

quint32 GearClient::sequence() const {
    return sequence_;
}

void GearClient::requestGear(const QString& gear, const QString& source) {
    if (!iface_.isValid()) {
        qWarning() << "[GearClient] Cannot request gear; interface invalid";
        return;
    }

    const quint8 gearCode = gearStringToCode(gear);
    const QString sender = sanitizeSource(source);

    QDBusPendingCall pending = iface_.asyncCall(
        QStringLiteral("RequestGear"),
        QVariant::fromValue(gearCode),
        sender);

    auto* watcher = new QDBusPendingCallWatcher(std::move(pending), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, &GearClient::handleRequestFinished);
}

void GearClient::refresh() {
    fetchInitialGear();
}

void GearClient::handleRequestFinished(QDBusPendingCallWatcher* watcher) {
    if (!watcher) {
        return;
    }

    QDBusPendingReply<QVariantList> reply = *watcher;

    if (reply.isError()) {
        const QString message = reply.error().message();
        qWarning() << "[GearClient] RequestGear call failed:" << message;
        emit gearRequestResult(false, sequence_, message);
        emit gearRequestRejected(message);
        watcher->deleteLater();
        return;
    }

    const QVariantList payload = reply.value();
    if (payload.size() < 3) {
        qWarning() << "[GearClient] Unexpected reply payload" << payload;
        emit gearRequestResult(false, sequence_, QStringLiteral("잘못된 응답"));
        watcher->deleteLater();
        return;
    }

    const bool accepted = payload.at(0).toBool();
    const quint32 seq = payload.at(1).toUInt();
    const QString reason = payload.at(2).toString();

    emit gearRequestResult(accepted, seq, reason);

    if (!accepted) {
        emit gearRequestRejected(reason.isEmpty() ? QStringLiteral("승인되지 않음") : reason);
    }

    watcher->deleteLater();
}

void GearClient::onGearChanged(quint8 gear, const QString& source, quint32 sequence) {
    Q_UNUSED(source);
    updateCurrentGear(gear, sequence);
}

void GearClient::onGearRequestRejected(quint8 gear, const QString& reason) {
    Q_UNUSED(gear);
    const QString message = reason.isEmpty() ? QStringLiteral("거부됨") : reason;
    emit gearRequestRejected(message);
}

void GearClient::subscribeToSignals() {
    if (signalsConnected_) {
        return;
    }

    QDBusConnection bus = gearBus();

    const bool changedConnected = bus.connect(
        QString::fromLatin1(ServiceName),
        QString::fromLatin1(ObjectPath),
        QString::fromLatin1(InterfaceName),
        QStringLiteral("GearChanged"),
        this,
        SLOT(onGearChanged(quint8,QString,quint32)));

    if (!changedConnected) {
        qWarning() << "[GearClient] Failed to subscribe to GearChanged:"
                   << bus.lastError().message();
    }

    const bool rejectedConnected = bus.connect(
        QString::fromLatin1(ServiceName),
        QString::fromLatin1(ObjectPath),
        QString::fromLatin1(InterfaceName),
        QStringLiteral("GearRequestRejected"),
        this,
        SLOT(onGearRequestRejected(quint8,QString)));

    if (!rejectedConnected) {
        qWarning() << "[GearClient] Failed to subscribe to GearRequestRejected:"
                   << bus.lastError().message();
    }

    signalsConnected_ = changedConnected && rejectedConnected;
}

void GearClient::fetchInitialGear() {
    if (!iface_.isValid()) {
        qWarning() << "[GearClient] Cannot fetch gear; interface invalid";
        return;
    }

    QDBusReply<QVariantList> reply = iface_.call(QStringLiteral("GetGear"));
    if (!reply.isValid()) {
        qWarning() << "[GearClient] GetGear call failed:" << reply.error().message();
        return;
    }

    const QVariantList payload = reply.value();
    if (payload.size() < 2) {
        qWarning() << "[GearClient] GetGear returned unexpected payload" << payload;
        return;
    }

    const quint8 gear = static_cast<quint8>(payload.at(0).toUInt());
    const quint32 seq = payload.at(1).toUInt();
    updateCurrentGear(gear, seq);
}

void GearClient::updateCurrentGear(quint8 gear, quint32 sequence) {
    const QString nextGear = gearCodeToString(gear);

    if (nextGear != currentGear_) {
        currentGear_ = nextGear;
        emit currentGearChanged();
    }

    if (sequence != sequence_) {
        sequence_ = sequence;
        emit sequenceChanged();
    }
}

QString GearClient::gearCodeToString(quint8 gear) const {
    switch (gear) {
    case GearNeutral:
        return QStringLiteral("N");
    case GearDrive:
        return QStringLiteral("D");
    case GearReverse:
        return QStringLiteral("R");
    case GearPark:
        return QStringLiteral("P");
    default:
        qWarning() << "[GearClient] Unknown gear code:" << gear;
        return QStringLiteral("N");
    }
}

quint8 GearClient::gearStringToCode(const QString& gear) const {
    const QString normalized = gear.trimmed().toUpper();
    if (normalized == QStringLiteral("N")) {
        return GearNeutral;
    }
    if (normalized == QStringLiteral("D")) {
        return GearDrive;
    }
    if (normalized == QStringLiteral("R")) {
        return GearReverse;
    }
    if (normalized == QStringLiteral("P")) {
        return GearPark;
    }

    qWarning() << "[GearClient] Unknown gear string:" << gear;
    return GearNeutral;
}

QString GearClient::sanitizeSource(const QString& source) const {
    const QString trimmed = source.trimmed();
    if (trimmed.isEmpty()) {
        return QString::fromLatin1(DefaultSource);
    }
    return trimmed.left(32); // Safety bound
}
