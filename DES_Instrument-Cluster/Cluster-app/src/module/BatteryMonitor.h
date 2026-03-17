#ifndef BATTERYMONITOR_H
# define BATTERYMONITOR_H

# include "INA219.h"
# include "BatterySoc.h"

# include <deque>

class BatteryMonitor : public INA219, public BatterySOC {
	public:
		BatteryMonitor();
		~BatteryMonitor();

		int getSoc();
		bool isConnected();

	private:
		// Battery helper's init values
		static constexpr int INA219_I2C_BUS = 1;
		static constexpr uint8_t INA219_ADDRESS = 0x41;
		static constexpr int BTRYSOC_CELLS_SERIES = 3;

		// Count of sample to get average
		static constexpr size_t FILTER_RANGE = 10;

		// Ignore function call if voltage drops above this value
		static constexpr float THRESHOLD = 0.03f; 
		
		INA219 _chip;
		BatterySOC _converter;

		std::deque<float> _vrecord;
		float _sum = 0, _average = 0;

		float _filterAbnormalDrop(float);
};


#endif