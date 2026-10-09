-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"

local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local TemperatureMeasurement = clusters.TemperatureMeasurement

local function active_power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 10

  raw_value = raw_value / divisor

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function rms_voltage_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.voltageMeasurement.voltage({value = value.value, unit = "V"}))
end

local function rms_current_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.currentMeter.current({value = value.value, unit = "A"}))
end

local function metering_handler(driver, device, value, zb_rx)
  local raw_value = value.value / 1000  -- Convert Wh to kWh
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh"}))
end

local function temperature_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("ZIGBEE GENERIC SWITCHPOWER TEMPERATURE HANDLER CALLED")
  log.info("========================================")
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = value.value / 100, unit = "C"}))
end

local zigbee_switch_power = {
  NAME = "Zigbee Switch Power",
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_meter_handler,
        [ElectricalMeasurement.attributes.RMSVoltage.ID] = rms_voltage_handler,
        [ElectricalMeasurement.attributes.RMSCurrent.ID] = rms_current_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler,
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = metering_handler

      },
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_handler
      }
    }
  },
  sub_drivers = require("zigbee-switch-power.sub_drivers"),
  can_handle = require("zigbee-switch-power.can_handle"),
}

return zigbee_switch_power
