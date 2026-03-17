#ifndef MODULE_GEARMANAGER_H
#define MODULE_GEARMANAGER_H

#include <QObject>
#include <QString>
#include <QtDBus/QDBusConnection> 
#include <QtGlobal>
#include <QVariant>
#include <memory>

class SharedMemory; //전방 선언 //.cpp에서 헤더를 include

class GearManager : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.des.vehicle.Gear")

public:
    explicit GearManager(QObject* parent = nullptr);
    ~GearManager() override; //D-Bus 서비스 등록 해제 //unregisterFromBus() 호출

    void setVehicleMemory(const std::shared_ptr<SharedMemory>& vehicle);
    void updateFromCluster(const QString& gear, const QString& source = QStringLiteral("InstrumentCluster"));
    bool isRegistered() const { return registered_; }

public slots:
    // QVariantList는 QList<QVariant>의 별칭
    QList<QVariant> RequestGear(quint8 gear, const QString& source);
    QVariantList GetGear() const; 

signals:
    void GearChanged(quint8 gear, const QString& source, quint32 seq); //이걸 구독하면 상태 변화를 실시간으로 받을 수 있음
    void GearRequestRejected(quint8 gear, const QString& reason);

private:
    bool registerOnBus();  //register D-Bus service for gear_client to use
    void unregisterFromBus();
    bool isAllowed(quint8 gear, const QString& source) const;
    bool setCurrentGear(quint8 gear, const QString& source);
    void writeGearToSharedMemory(quint8 gear); 
    QString sanitizeSource(const QString& source) const;
    quint8 gearStringToCode(const QString& gear) const;

    quint8 gear_ = 0;  // NEUTRAL
    quint32 seq_ = 0;
    bool registered_ = false;
    std::weak_ptr<SharedMemory> vehicle_;
};

#endif // MODULE_GEARMANAGER_H
