-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local log = require "log"

-- Sinopé manufacturer cluster and attributes
local SINOPE_SWITCH_CLUSTER               = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE   = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE  = 0x0053
local SINOPE_CONNECTED_LOAD_ATTR          = 0x0060  -- ConnectedLoad (W)[web:45]
local SINOPE_CURRENT_LOAD_ATTR            = 0x0070  -- CurrentLoad (W-ish bitmap)[web:45]
local SINOPE_DR_MIN_WATER_TEMP_ATTR       = 0x0076  -- drConfigWaterTempMin (°C)[web:45]
local SINOPE_DR_MIN_WATER_TEMP_TIME_ATTR  = 0x0077  -- drConfigWaterTempTime[web:45]
local SINOPE_TIMER_ATTR                   = 0x00A0  -- Timer seconds[web:45]
local SINOPE_TIMER_COUNTDOWN_ATTR         = 0x00A1  -- Timer_countDown[web:45]
local SINOPE_MIN_MEASURED_TEMP_ATTR       = 0x007C  -- min_measured_temp (°C×100)[web:45]
local SINOPE_MAX_MEASURED_TEMP_ATTR       = 0x007D  -- max_measured_temp (°C×100)[web:45]
local SINOPE_ENERGY_INTERNAL_ATTR         = 0x0090  -- currentSummationDelivered (internal)[web:45]

-- Standard Zigbee clusters
local SimpleMetering          = clusters.SimpleMetering -- 0x0702
local OnOff                   = clusters.OnOff          -- 0x0006
local TemperatureMeasurement  = clusters.TemperatureMeasurement -- 0x0402
local IASZone                 = clusters.IASZone        -- 0x0500
local ElectricalMeasurement   = clusters.ElectricalMeasurement   -- 0x0B04
local Thermostat              = clusters.Thermostat

--Water mon temp config
-- Cluster: 0xff01
-- Attribute: 0x0076
-- Data type: t.uint8_t
-- Function: drConfigWaterTempMin
-- Values: 45 or 0




-- Leak state from IAS Zone 0x0500/0x0002[web:45]
local function water_sensor_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB LEAK HANDLER CALLED")
  local zone_status = value.value
  local wet = (bit32.band(zone_status, 0x0001) ~= 0)  -- example mask
  if wet then
    device:emit_event(capabilities.waterSensor.water.wet())
  else
    device:emit_event(capabilities.waterSensor.water.dry())
  end
end

-- Active power from 0x0B04/0x050B[web:45]
local function active_power_meter_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB POWERMETER HANDLER CALLED")
  local raw_value = value.value
  raw_value = raw_value / 10

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB INSTANTMETER HANDLER CALLED")
  local raw_value = value.value
  raw_value = raw_value / 10

  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W"}))
end

local function rms_voltage_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB RMSVOLTS HANDLER CALLED")
  device:emit_event(capabilities.voltageMeasurement.voltage({value = value.value, unit = "V"}))
end

local function rms_current_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB RMS CURRENT HANDLER CALLED")
  device:emit_event(capabilities.currentMeasurement.current({value = value.value, unit = "A"}))
end

local function metering_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB ENERGYMETER HANDLER CALLED")
  local raw_value = value.value / 1000  -- Convert Wh to kWh
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh"}))
end

local function temperature_handler(driver, device, value, zb_rx)
  log.info("========================================")
  log.info("RM3500ZB TEMPERATURE HANDLER CALLED")
  log.info("========================================")
  local temp_c = value.value /100
  -- the RM3500ZB may report 2 types of values with one in the -300 range. This only sends the value if it is over -100 deg C
  if temp_c > -100 then
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = value.value / 100, unit = "C"}))
    return
  end
end

-- ============================================================================
-- CONFIGURE HANDLER - Set reporting intervals
-- ============================================================================

local function configure_device(driver, device)
  log.info("========================================")
  log.info("RM3500ZB CONFIGURE DEVICE HANDLER CALLED")
  log.info("========================================")

  -- Configure Temperature reporting (every 30s to 5min, on 0.5°C change)
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
    device,
    60,    -- min_report_interval (seconds)
    900,   -- max_report_interval (seconds)
    50     -- reportable_change (0.5°C, in 0.01°C units)
  ))

  -- Configure Power reporting (every 10s to 60s, on 5W change)
  device:send(SimpleMetering.attributes.InstantaneousDemand:configure_reporting(
    device,
    10,    -- min interval: 10 seconds
    900,    -- max interval: 15 minute
    50     -- reportable change: 5W (in 0.1W units)
  ))

  -- Configure Energy reporting (every 5min to 30min, on 0.01 kWh change)
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(
    device,
    300,   -- min interval: 5 minutes
    1800,  -- max interval: 30 minutes
    10     -- reportable change: 0.01 kWh (in 0.001 kWh units)
  ))

  -- Configure Voltage reporting (every 60s to 5min, on 1V change)
  device:send(ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(
    device,
    60,    -- min interval: 1 minute
    1800,   -- max interval: 30 minutes
    10     -- reportable change: 1V (in 0.1V units)
  ))

  -- Configure Current reporting (every 10s to 60s, on 0.1A change)
  device:send(ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(
    device,
    10,    -- min interval: 10 seconds
    900,    -- max interval: 15 minute
    500    -- reportable change: 0.1A (in 0.001A units)
  ))

  -- Configure IAS Zone reporting (water leak detection)
  device:send(IASZone.attributes.ZoneStatus:configure_reporting(
    device,
    0,     -- min interval: immediate
    1800,   -- max interval: 30 minutes
    1      -- reportable change: any change
  ))

  -- Configure On/Off reporting
  device:send(OnOff.attributes.OnOff:configure_reporting(
    device,
    0,     -- min interval: immediate
    1800,   -- max interval: 30 minutes
    1      -- reportable change: any change
  ))

  -- Refresh all values after configuration
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(SimpleMetering.attributes.InstantaneousDemand:read(device))
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  device:send(ElectricalMeasurement.attributes.RMSVoltage:read(device))
  device:send(ElectricalMeasurement.attributes.RMSCurrent:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

local function do_refresh(driver, device)
  log.info("========================================")
  log.info("RM3500ZB DOREFRESH HANDLER CALLED")
  log.info("========================================")
  
  -- Refresh all values
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(SimpleMetering.attributes.InstantaneousDemand:read(device))
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
  device:send(ElectricalMeasurement.attributes.RMSVoltage:read(device))
  device:send(ElectricalMeasurement.attributes.RMSCurrent:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

-- ============================================================================
-- DRIVER DEFINITION
-- ============================================================================

local sinope_rm3500zb = {
  NAME = "Sinopé RM3500ZB Water Heater",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    init = configure_device,  -- Called when device is added/configured
  },
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
      },
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = water_sensor_handler
      },
    },
  },
  can_handle = require("sinope-waterheater.can_handle")
}


return sinope_rm3500zb



