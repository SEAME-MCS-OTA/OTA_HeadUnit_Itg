#ifndef BACKEND_GEAR_GEAR_CLIENT_H
#define BACKEND_GEAR_GEAR_CLIENT_H

#include <QObject>
#include <QString>
#include <QtDBus/QDBusInterface>
#include <QtGlobal>

class QDBusPendingCallWatcher;

class GearClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentGear READ currentGear NOTIFY currentGearChanged)
    Q_PROPERTY(quint32 sequence READ sequence NOTIFY sequenceChanged)

public:
    explicit GearClient(QObject* parent = nullptr); //initializer why explicit? to prevent implicit conversions.

    QString currentGear() const; //getter
    quint32 sequence() const; //getter

    Q_INVOKABLE void requestGear(const QString& gear, const QString& source = QString());
    Q_INVOKABLE void refresh(); //what is Q_INVOKABLE? Makes the method invokable via Qt's meta-object system, e.g., from QML.

signals:
    void currentGearChanged();
    void sequenceChanged();
    void gearRequestResult(bool accepted, quint32 sequence, const QString& reason);
    void gearRequestRejected(const QString& reason);

private slots:
    void handleRequestFinished(QDBusPendingCallWatcher* watcher);
    void onGearChanged(quint8 gear, const QString& source, quint32 sequence);
    void onGearRequestRejected(quint8 gear, const QString& reason);

private:
    void subscribeToSignals(); //is it member function? Yes, it's a private member function. why is it private? To restrict access to within the class itself.  So other classes cannot call it directly
    void fetchInitialGear(); //private member function
    void updateCurrentGear(quint8 gear, quint32 sequence); //private member function
    QString gearCodeToString(quint8 gear) const; 
    quint8 gearStringToCode(const QString& gear) const;
    QString sanitizeSource(const QString& source) const;

    QDBusInterface iface_;
    QString currentGear_; //members (from QObject)
    quint32 sequence_; //members (from QObject)
    bool signalsConnected_; //members (from QObject)
};

#endif // BACKEND_GEAR_GEAR_CLIENT_H
