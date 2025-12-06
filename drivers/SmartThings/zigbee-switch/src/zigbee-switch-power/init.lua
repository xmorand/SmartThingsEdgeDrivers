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

local zigbee_switch_power = {
  NAME = "Zigbee Switch Power",
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = instantaneous_demand_handler
      }
    }
  },
  sub_drivers = require("zigbee-switch-power.sub_drivers"),
  can_handle = require("zigbee-switch-power.can_handle"),
}

return zigbee_switch_power


local function electrical_measurement_handler(driver, device, value, raw)
  if value.attr_id == 0x0400 then  -- Active Power
    device:emit_event(capabilities.powerMeter.power({value = value.value, unit = "W"}))
  elseif value.attr_id == 0x0505 then  -- RMS Voltage
    device:emit_event(capabilities.voltageMeasurement.voltage({value = value.value, unit = "V"}))
  elseif value.attr_id == 0x0508 then  -- RMS Current
    device:emit_event(capabilities.currentMeter.current({value = value.value, unit = "A"}))
  end
end

local function metering_handler(driver, device, value, raw)
  if value.attr_id == 0x0000 then  -- Cumulative Energy
    device:emit_event(capabilities.energyMeter.energy({value = value.value / 1000, unit = "kWh"}))
  end
end

local function temperature_handler(driver, device, value, raw)
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = value.value / 100, unit = "C"}))
end
