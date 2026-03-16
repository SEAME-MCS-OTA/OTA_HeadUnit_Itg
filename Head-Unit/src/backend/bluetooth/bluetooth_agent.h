#ifndef BACKEND_BLUETOOTH_BLUETOOTH_AGENT_H
#define BACKEND_BLUETOOTH_BLUETOOTH_AGENT_H

#include <QObject>
#include <QString>
#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QDBusContext>

/**
 * @brief BlueZ Agent implementation for handling Bluetooth pairing authentication
 *
 * Implements org.bluez.Agent1 D-Bus interface to handle:
 * - PIN code requests
 * - Passkey confirmation (6-digit number YES/NO)
 * - Passkey display
 * - Authorization requests
 *
 * This is necessary to properly handle pairing requests that bluetoothctl sends.
 */
class BluetoothAgent : public QDBusAbstractAdaptor, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
    Q_CLASSINFO("D-Bus Context", "true")

public:
    explicit BluetoothAgent(QObject* parent = nullptr);
    ~BluetoothAgent();

signals:
    // Emitted when user needs to confirm a passkey (YES/NO dialog)
    void passkeyConfirmationRequested(const QString& devicePath, const QString& deviceName, quint32 passkey);

    // Emitted when user needs to enter a PIN code
    void pinCodeRequested(const QString& devicePath, const QString& deviceName);

    // Emitted when passkey should be displayed to user
    void passkeyDisplayRequested(const QString& devicePath, const QString& deviceName, quint32 passkey, quint16 entered);

    // Emitted when pairing was cancelled
    void pairingCancelled();

    // Response signals (internal)
    void confirmationResponseReady(bool accepted);
    void pinCodeResponseReady(const QString& pinCode);

public slots:
    // D-Bus methods (called by BlueZ)
    Q_SCRIPTABLE void RequestConfirmation(const QDBusObjectPath& device, quint32 passkey);
    Q_SCRIPTABLE QString RequestPinCode(const QDBusObjectPath& device);
    Q_SCRIPTABLE quint32 RequestPasskey(const QDBusObjectPath& device);
    Q_SCRIPTABLE void DisplayPasskey(const QDBusObjectPath& device, quint32 passkey, quint16 entered);
    Q_SCRIPTABLE void DisplayPinCode(const QDBusObjectPath& device, const QString& pincode);
    Q_SCRIPTABLE void RequestAuthorization(const QDBusObjectPath& device);
    Q_SCRIPTABLE void AuthorizeService(const QDBusObjectPath& device, const QString& uuid);
    Q_SCRIPTABLE void Cancel();
    Q_SCRIPTABLE void Release();

    // Application methods (called from UI)
    void confirmPairing(bool accepted);
    void providePinCode(const QString& pinCode);
    void providePasskey(quint32 passkey);

private:
    QString getDeviceName(const QString& devicePath);

    // Pending request tracking
    QString pendingDevicePath_;
    bool waitingForConfirmation_ = false;
    bool waitingForPinCode_ = false;
    bool waitingForPasskey_ = false;

    // Response values
    bool confirmationResponse_ = false;
    QString pinCodeResponse_;
    quint32 passkeyResponse_ = 0;
};

#endif // BACKEND_BLUETOOTH_BLUETOOTH_AGENT_H
