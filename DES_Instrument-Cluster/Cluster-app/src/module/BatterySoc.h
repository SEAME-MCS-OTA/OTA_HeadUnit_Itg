#ifndef BATTERYSOC_H
#define BATTERYSOC_H

#include <vector>
#include <utility>
#include <algorithm>

/**
 * @brief Battery State of Charge (SoC) Calculator
 *
 * Converts battery voltage to State of Charge percentage using
 * a lookup table with linear interpolation.
 */
class BatterySOC {
public:
    // Voltage-SoC pair type
    using VoltageSocPair = std::pair<double, double>;

    /**
     * @brief Constructor with default 3S battery configuration
     * @param cells_in_series Number of cells connected in series (default: 3)
     */
    explicit BatterySOC(int cells_in_series = 3);

    /**
     * @brief Constructor with custom voltage-SoC table
     * @param voltage_soc_table Custom lookup table (voltage per cell, SoC%)
     * @param cells_in_series Number of cells connected in series
     */
    BatterySOC(const std::vector<VoltageSocPair>& voltage_soc_table, int cells_in_series);

    /**
     * @brief Convert total battery voltage to State of Charge percentage
     * @param total_voltage Total battery pack voltage
     * @return SoC percentage (0.0 to 100.0)
     */
    double voltageToSoC(double total_voltage) const;

    /**
     * @brief Get the voltage per cell for a given total voltage
     * @param total_voltage Total battery pack voltage
     * @return Voltage per individual cell
     */
    double getVoltagePerCell(double total_voltage) const;

    /**
     * @brief Set the number of cells in series
     * @param cells Number of cells in series
     */
    void setCellsInSeries(int cells);

    /**
     * @brief Get the number of cells in series
     * @return Number of cells in series
     */
    int getCellsInSeries() const;

    /**
     * @brief Set custom voltage-SoC lookup table
     * @param table Vector of voltage-SoC pairs (must be sorted by voltage descending)
     */
    void setVoltageSocTable(const std::vector<VoltageSocPair>& table);

    /**
     * @brief Get the current voltage-SoC lookup table
     * @return Reference to the voltage-SoC table
     */
    const std::vector<VoltageSocPair>& getVoltageSocTable() const;

private:
    std::vector<VoltageSocPair> voltage_soc_table_;
    int cells_in_series_;

    /**
     * @brief Initialize default voltage-SoC table for lithium-ion cells
     */
    void initializeDefaultTable();

    /**
     * @brief Validate that the voltage-SoC table is properly sorted
     * @return true if table is valid, false otherwise
     */
    bool isTableValid() const;
};

#endif // BATTERYSOC_H
