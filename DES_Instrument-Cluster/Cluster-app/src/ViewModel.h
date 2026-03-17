#ifndef VIEWMODEL_H
# define VIEWMODEL_H

# include "BatteryMonitor.h"
# include "SharedMemory.h"

# include <QObject>
# include <QTimer>
# include <QByteArray>
# include <QtGlobal>

# include <unordered_map>

# define WHEEL_DIAMETER 6.8 // cm
# define PI 3.1415

class ViewModel : public QObject {
	/* QT FRAMEWORK */
	Q_OBJECT
	Q_PROPERTY(QString driveMode READ driveMode NOTIFY updateDriveMode)
	Q_PROPERTY(int capacity READ capacity NOTIFY updateCapacity)
	Q_PROPERTY(int speed READ speed NOTIFY updateSpeed)

	public slots:  
		void receiveTimeout(const std::string&);
		void receiveCanData(int, const QByteArray&);
		void applyGearUpdate(quint8 gearCode);

	signals:
		void updateCapacity();
		void updateDriveMode();
		void updateSpeed();

	/* CLASS */
	public:
		enum can_id_e {
			ID_RPM = 0x10
		};

		enum timer_id_e {
			ID_BATTERY,
			ID_DRIVE_MODE
		};

		static const std::unordered_map<std::string, timer_id_e> timer_name_id_map;

		enum drive_mode_e {
			NEUTRAL,
			DRIVE,
			REVERSE,
			PARKING
		};

		static const std::unordered_map<drive_mode_e, QString> drive_mode_alpha_map;

		explicit ViewModel(QObject* parent = nullptr);
		~ViewModel();

		int capacity() const { return _capacity; } 
		int speed() const { return _speed; }
		QString driveMode() const { return _driveMode; }

		void setVehicle(const std::shared_ptr<SharedMemory>&);
		void setBattery(const std::shared_ptr<BatteryMonitor>&);

	private:
		std::shared_ptr<BatteryMonitor> _battery = nullptr;
		int _capacity = 0;

		std::shared_ptr<SharedMemory> _vehicle = nullptr;
		QString _driveMode = "N";

		int _speed = 0; 

		int _int(const QByteArray&, int) const;
		drive_mode_e _getDriveMode() const;
};

#endif
