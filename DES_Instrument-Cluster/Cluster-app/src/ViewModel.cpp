#include "ViewModel.h"

#include <QDebug>

const std::unordered_map<std::string, ViewModel::timer_id_e> ViewModel::timer_name_id_map = {
	{"battery", ID_BATTERY},
	{"drivemode", ID_DRIVE_MODE}
};

const std::unordered_map<ViewModel::drive_mode_e, QString> ViewModel::drive_mode_alpha_map = {
	{NEUTRAL,	"N"},
	{DRIVE,		"D"},
	{REVERSE,	"R"},
	{PARKING,	"P"}
};

/* CON & DESTRUCTOR */
ViewModel::ViewModel(QObject *parent)
	: QObject(parent) {}

ViewModel::~ViewModel() {}

/* QT SLOTS */
void ViewModel::receiveTimeout(const std::string& name) {
	switch (timer_name_id_map.at(name)) {
		case ID_BATTERY: {
			_capacity = _battery->getSoc();
			emit updateCapacity();
			break;
		}

		case ID_DRIVE_MODE: {
			_driveMode = drive_mode_alpha_map.at(_getDriveMode());
			emit updateDriveMode();
			break;
		}

		default: qWarning() << "[IC] Unreserved TIMER_ID received";
	}
}

void ViewModel::receiveCanData(int canID, const QByteArray& data) {
	switch (canID) {
		case ID_RPM: {
			if (data.size() < 2) {
				qWarning() << "[ViewModel] RPM frame too short:" << data.size();
				break;
			}

			/* Convert RPM to speed using wheel diameter
			Speed = (wheel circumference * RPM) / 60 (to get per second)
			Result in cm/s as per your original implementation */
			int val = static_cast<int>(WHEEL_DIAMETER * PI * static_cast<float>(_int(data, 0)) / 60.0f);
			if (val != _speed) {
				_speed = val;
				emit updateSpeed();
			}
			break;
		}

		default: qDebug() << "[ViewModel] Unreserved CAN_ID received:" << Qt::hex << canID;
	}
}

/* CLASS METHODS */
void ViewModel::setVehicle(const std::shared_ptr<SharedMemory>& ptr) {
	_vehicle = ptr;	
}

void ViewModel::setBattery(const std::shared_ptr<BatteryMonitor>& ptr) {
	_battery = ptr;	
}

void ViewModel::applyGearUpdate(quint8 gearCode) {
	if (gearCode > static_cast<quint8>(PARKING)) {
		qWarning() << "[ViewModel] Ignoring invalid gear code:" << gearCode;
		return;
	}

	const auto mode = static_cast<drive_mode_e>(gearCode);
	const auto it = drive_mode_alpha_map.find(mode);
	if (it == drive_mode_alpha_map.end()) {
		qWarning() << "[ViewModel] Gear code not mapped:" << gearCode;
		return;
	}

	const QString next = it->second;
	if (_driveMode != next) {
		_driveMode = next;
		emit updateDriveMode();
	}

	if (_vehicle && _vehicle->isValid()) {
		auto* data = static_cast<int*>(_vehicle->getMemoryPtr());
		if (data) {
			const int value = static_cast<int>(mode);
			if (*data != value) {
				*data = value;
				_vehicle->sync();
			}
		}
	}
}

int ViewModel::_int(const QByteArray& data, int pos = 0) const {
	if (pos + 1 >= data.size()) {
		return 0;
	}
	
	// Parse as big-endian 16-bit integer
	return (static_cast<unsigned char>(data[pos]) << 8) | 
			static_cast<unsigned char>(data[pos + 1]);
}

ViewModel::drive_mode_e ViewModel::_getDriveMode() const {
	int* data = static_cast<int*>(_vehicle->getMemoryPtr());
	if (data) {
		int mode = *data;
		
		if (mode < NEUTRAL || mode > PARKING) {
			qWarning() << "[ViewModel] Invalid drive mode value from shared memory:" << mode;
		} else {
			return static_cast<drive_mode_e>(mode);
		}
	}
    return NEUTRAL;
}
