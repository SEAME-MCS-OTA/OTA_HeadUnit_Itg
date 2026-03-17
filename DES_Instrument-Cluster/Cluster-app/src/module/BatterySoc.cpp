#include "BatterySoc.h"
#include <stdexcept>
#include <cmath>

BatterySOC::BatterySOC(int cells_in_series)
    : cells_in_series_(cells_in_series) {
    if (cells_in_series <= 0) {
        throw std::invalid_argument("Number of cells must be positive");
    }
    initializeDefaultTable();
}

BatterySOC::BatterySOC(const std::vector<VoltageSocPair>& voltage_soc_table, int cells_in_series)
    : voltage_soc_table_(voltage_soc_table), cells_in_series_(cells_in_series) {
    if (cells_in_series <= 0) {
        throw std::invalid_argument("Number of cells must be positive");
    }
    if (!isTableValid()) {
        throw std::invalid_argument("Voltage-SoC table must be sorted by voltage in descending order");
    }
}

void BatterySOC::initializeDefaultTable() {
    // Default voltage to SoC lookup table for 1 lithium-ion cell
    // Values based on typical Li-ion discharge curve
    voltage_soc_table_ = {
        {4.145, 100.0},
        {4.10, 93.0},
        {4.05, 85.0},
        {4.00, 80.0},
        {3.95, 70.0},
        {3.87, 60.0},
        {3.82, 50.0},
        {3.79, 40.0},
        {3.75, 30.0},
        {3.70, 20.0},
        {3.60, 10.0},
        {3.50, 0.0}
    };
}

double BatterySOC::voltageToSoC(double total_voltage) const {
    if (voltage_soc_table_.empty()) {
        throw std::runtime_error("Voltage-SoC table is empty");
    }

    // Calculate voltage per cell
    double voltage_per_cell = total_voltage / cells_in_series_;

    // Check boundary conditions
    if (voltage_per_cell >= voltage_soc_table_.front().first) {
        return 100.0;
    }
    if (voltage_per_cell <= voltage_soc_table_.back().first) {
        return 0.0;
    }

    // Find the appropriate range for interpolation
    // The table is sorted in descending order by voltage
    for (size_t i = 0; i < voltage_soc_table_.size() - 1; ++i) {
        double v1 = voltage_soc_table_[i].first;
        double soc1 = voltage_soc_table_[i].second;
        double v2 = voltage_soc_table_[i + 1].first;
        double soc2 = voltage_soc_table_[i + 1].second;

        if (voltage_per_cell <= v1 && voltage_per_cell >= v2) {
            // Linear interpolation between two points
            double soc = soc1 + (voltage_per_cell - v1) * (soc2 - soc1) / (v2 - v1);
            return std::max(0.0, std::min(100.0, soc)); // Clamp to 0-100 range
        }
    }

    // This should never be reached if the table is properly sorted
    return 0.0;
}

double BatterySOC::getVoltagePerCell(double total_voltage) const {
    return total_voltage / cells_in_series_;
}

void BatterySOC::setCellsInSeries(int cells) {
    if (cells <= 0) {
        throw std::invalid_argument("Number of cells must be positive");
    }
    cells_in_series_ = cells;
}

int BatterySOC::getCellsInSeries() const {
    return cells_in_series_;
}

void BatterySOC::setVoltageSocTable(const std::vector<VoltageSocPair>& table) {
    voltage_soc_table_ = table;
    if (!isTableValid()) {
        throw std::invalid_argument("Voltage-SoC table must be sorted by voltage in descending order");
    }
}

const std::vector<BatterySOC::VoltageSocPair>& BatterySOC::getVoltageSocTable() const {
    return voltage_soc_table_;
}

bool BatterySOC::isTableValid() const {
    if (voltage_soc_table_.empty()) {
        return false;
    }

    // Check that voltages are in descending order
    for (size_t i = 0; i < voltage_soc_table_.size() - 1; ++i) {
        if (voltage_soc_table_[i].first <= voltage_soc_table_[i + 1].first) {
            return false;
        }
    }

    return true;
}
