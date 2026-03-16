#include "bluetooth_agent.h"
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusError>
#include <QDebug>
#include <QEventLoop>
#include <QTimer>

BluetoothAgent::BluetoothAgent(QObject* parent)
    : QDBusAbstractAdaptor(parent) {

    setAutoRelaySignals(true);
    qDebug() << "[BluetoothAgent] Agent created";
}

BluetoothAgent::~BluetoothAgent() {
    qDebug() << "[BluetoothAgent] Agent destroyed";
}

void BluetoothAgent::RequestConfirmation(const QDBusObjectPath& device, quint32 passkey) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] RequestConfirmation from" << deviceName << "with passkey" << passkey;
    qDebug() << "[BluetoothAgent] ✅ AUTO-ACCEPTING pairing";

    // void return = automatic success response
    // Qt D-Bus automatically sends empty method_return when function returns normally
}

QString BluetoothAgent::RequestPinCode(const QDBusObjectPath& device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] RequestPinCode:"
             << "Device:" << deviceName;

    pendingDevicePath_ = devicePath;

    // Auto-provide default PIN code "0000" (most common for Bluetooth devices)
    QString defaultPin = "0000";
    qDebug() << "[BluetoothAgent] ✅ AUTO-PROVIDING PIN code:" << defaultPin;

    // Optional: emit signal to show notification in UI
    emit pinCodeRequested(devicePath, deviceName);

    return defaultPin;
}

quint32 BluetoothAgent::RequestPasskey(const QDBusObjectPath& device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] RequestPasskey:"
             << "Device:" << deviceName;

    pendingDevicePath_ = devicePath;

    // Auto-provide default passkey 000000
    quint32 defaultPasskey = 0;
    qDebug() << "[BluetoothAgent] ✅ AUTO-PROVIDING passkey:" << defaultPasskey;

    // Optional: emit signal to show notification in UI
    emit pinCodeRequested(devicePath, deviceName);

    return defaultPasskey;
}

void BluetoothAgent::DisplayPasskey(const QDBusObjectPath& device, quint32 passkey, quint16 entered) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] DisplayPasskey:"
             << "Device:" << deviceName
             << "Passkey:" << passkey
             << "Entered:" << entered;

    emit passkeyDisplayRequested(devicePath, deviceName, passkey, entered);

    // This is a notification method, no response needed
}

void BluetoothAgent::DisplayPinCode(const QDBusObjectPath& device, const QString& pincode) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] DisplayPinCode:"
             << "Device:" << deviceName
             << "PIN:" << pincode;

    // Display the PIN to user (they need to enter it on their phone)
    emit passkeyDisplayRequested(devicePath, deviceName, pincode.toUInt(), 0);
}

void BluetoothAgent::RequestAuthorization(const QDBusObjectPath& device) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] RequestAuthorization for" << deviceName;
    qDebug() << "[BluetoothAgent] ✅ AUTO-ACCEPTING authorization";

    // void return = automatic success response
    // Qt D-Bus automatically sends empty method_return when function returns normally
}

void BluetoothAgent::AuthorizeService(const QDBusObjectPath& device, const QString& uuid) {
    QString devicePath = device.path();
    QString deviceName = getDeviceName(devicePath);

    qDebug() << "[BluetoothAgent] AuthorizeService for" << deviceName << "with UUID" << uuid;
    qDebug() << "[BluetoothAgent] ✅ AUTO-ACCEPTING service";

    // void return = automatic success response
    // Qt D-Bus automatically sends empty method_return when function returns normally
}

void BluetoothAgent::Cancel() {
    qDebug() << "[BluetoothAgent] Pairing cancelled by system";

    waitingForConfirmation_ = false;
    waitingForPinCode_ = false;
    waitingForPasskey_ = false;

    emit pairingCancelled();
}

void BluetoothAgent::Release() {
    qDebug() << "[BluetoothAgent] Agent released by BlueZ";
    // Agent is being unregistered
}

void BluetoothAgent::confirmPairing(bool accepted) {
    qDebug() << "[BluetoothAgent] confirmPairing called from UI, accepted:" << accepted;

    if (!waitingForConfirmation_) {
        qWarning() << "[BluetoothAgent] No confirmation pending!";
        return;
    }

    qDebug() << "[BluetoothAgent] User response received, completing D-Bus call...";
    confirmationResponse_ = accepted;
    emit confirmationResponseReady(accepted);
}

void BluetoothAgent::providePinCode(const QString& pinCode) {
    if (!waitingForPinCode_ && !waitingForPasskey_) {
        qWarning() << "[BluetoothAgent] No PIN code request pending";
        return;
    }

    pinCodeResponse_ = pinCode;
    emit pinCodeResponseReady(pinCode);
}

void BluetoothAgent::providePasskey(quint32 passkey) {
    if (!waitingForPasskey_) {
        qWarning() << "[BluetoothAgent] No passkey request pending";
        return;
    }

    passkeyResponse_ = passkey;
    pinCodeResponse_ = QString::number(passkey);
    emit pinCodeResponseReady(pinCodeResponse_);
}

QString BluetoothAgent::getDeviceName(const QString& devicePath) {
    QDBusInterface device("org.bluez", devicePath, "org.bluez.Device1",
                         QDBusConnection::systemBus());

    if (!device.isValid()) {
        qWarning() << "[BluetoothAgent] Invalid device path:" << devicePath;
        return "Unknown Device";
    }

    QVariant nameVar = device.property("Name");
    if (nameVar.isValid()) {
        return nameVar.toString();
    }

    // Extract address from path as fallback
    QString address = devicePath;
    int devIndex = address.lastIndexOf("/dev_");
    if (devIndex != -1) {
        address = address.mid(devIndex + 5);
        address.replace('_', ':');
        return address;
    }

    return "Unknown Device";
}
