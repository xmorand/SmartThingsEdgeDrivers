-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- local cluster_base = require "st.zigbee.cluster_base"
-- local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
-- local ZigbeeDriver = require "st.zigbee"
-- local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
-- local log = require "log"
local zb_utils = require "st.zigbee.utils"

-- Sinopé manufacturer cluster and attributes
-- local SINOPE_SWITCH_CLUSTER               = 0xFF01
-- local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE   = 0x0052
-- local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE  = 0x0053
-- local SINOPE_CONNECTED_LOAD_ATTR          = 0x0060  -- ConnectedLoad (W)
-- local SINOPE_CURRENT_LOAD_ATTR            = 0x0070  -- CurrentLoad (W-ish bitmap)
-- local SINOPE_DR_MIN_WATER_TEMP_ATTR       = 0x0076  -- drConfigWaterTempMin (°C)
-- local SINOPE_DR_MIN_WATER_TEMP_TIME_ATTR  = 0x0077  -- drConfigWaterTempTime
-- local SINOPE_TIMER_ATTR                   = 0x00A0  -- Timer seconds
-- local SINOPE_TIMER_COUNTDOWN_ATTR         = 0x00A1  -- Timer_countDown
-- local SINOPE_MIN_MEASURED_TEMP_ATTR       = 0x007C  -- min_measured_temp (°C×100)
-- local SINOPE_MAX_MEASURED_TEMP_ATTR       = 0x007D  -- max_measured_temp (°C×100)
-- local SINOPE_ENERGY_INTERNAL_ATTR         = 0x0090  -- currentSummationDelivered (internal)

-- Standard Zigbee clusters
local SimpleMetering          = clusters.SimpleMetering -- 0x0702
local OnOff                   = clusters.OnOff          -- 0x0006
local TemperatureMeasurement  = clusters.TemperatureMeasurement -- 0x0402
local IASZone                 = clusters.IASZone        -- 0x0500
local ElectricalMeasurement   = clusters.ElectricalMeasurement   -- 0x0B04
-- local Thermostat              = clusters.Thermostat
  

-- ============================================================================
-- STANDARD ATTRIBUTE HANDLERS
-- ============================================================================

-- Leak state from IAS Zone 0x0500/0x0002
local function water_sensor_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB LEAK HANDLER CALLED")
  local zone_status = value.value
  local wet = (bit32.band(zone_status, 0x0001) ~= 0)  -- example mask
  if wet then
    device:emit_event(capabilities.waterSensor.water.wet())
  else
    device:emit_event(capabilities.waterSensor.water.dry())
  end
end

-- Active power from 0x0B04/0x050B
local function active_power_meter_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB POWERMETER HANDLER CALLED")

  device:emit_event(capabilities.powerMeter.power({value = value.value, unit = "W"}))
end

local function instantaneous_demand_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB INSTANTMETER HANDLER CALLED")

  device:emit_event(capabilities.powerMeter.power({value = value.value, unit = "W"}))
end

local function rms_voltage_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB RMSVOLTS HANDLER CALLED")
  device:emit_event(capabilities.voltageMeasurement.voltage({value = value.value, unit = "V"}))
end

local function rms_current_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB RMS CURRENT HANDLER CALLED")
  local raw_value = value.value
  raw_value = raw_value / 1000

  device:emit_event(capabilities.currentMeasurement.current({value = raw_value, unit = "A"}))
end

local function metering_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB ENERGYMETER HANDLER CALLED")
  local raw_value = value.value / 1000  -- Convert Wh to kWh
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh"}))
end

local function temperature_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB TEMPERATURE HANDLER CALLED")
  -- log.info("========================================")
  local temp_c = value.value /100
  -- the RM3500ZB may report 2 types of values with one in the -300 range. This only sends the value if it is over -100 deg C
  if temp_c > -100 then
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = value.value / 100, unit = "C"}))
    return
  end
end

-- ============================================================================
-- SINOPE MANUFACTURER ATTRIBUTE HANDLERS
-- ============================================================================

-- Handler for Low Temperature Protection (0xFF01/0x0076)
local function sinope_low_temp_protection_handler(driver, device, value, zb_rx)
  -- log.info("========================================")
  -- log.info("RM3500ZB LOW TEMP PROTECTION HANDLER CALLED")
  local temp_value = value.value
  -- log.info(string.format("Low temp protection value from device: %d°C", temp_value))
  
  -- Store in field
  device:set_field("lowTempProtection", temp_value, {persist = true})
end

-- -- Handler for Tank Size (0xFF01/0x0060)
-- local function sinope_tank_size_handler(driver, device, value, zb_rx)
--   log.info("========================================")
--   log.info("RM3500ZB TANK SIZE HANDLER CALLED")
--   local tank_size = value.value
--   log.info(string.format("Tank size from device: %d Gallons", tank_size))
  
--   -- Store in field
--   device:set_field("tankSize", tank_size, {persist = true})
-- end

-- -- Handler for Min Measured Temp (0xFF01/0x007C) - READ ONLY
-- local function sinope_min_measured_temp_handler(driver, device, value, zb_rx)
--   log.info("========================================")
--   log.info("RM3500ZB MIN MEASURED TEMP HANDLER CALLED")
--   local temp_value = value.value / 100  -- Convert from °C×100
--   log.info(string.format("Min measured temp from device: %.2f°C", temp_value))
  
--   -- Store in field
--   device:set_field("minMeasuredTemp", temp_value, {persist = true})

--   -- -- Update the preference value (this makes it show in settings)
--   -- device:try_update_metadata({
--   --   preferences = {
--   --     minMeasuredTemp = temp_value
--   --   }
--   -- })
-- end

-- -- Handler for Max Measured Temp (0xFF01/0x007D) - READ ONLY
-- local function sinope_max_measured_temp_handler(driver, device, value, zb_rx)
--   log.info("========================================")
--   log.info("RM3500ZB MAX MEASURED TEMP HANDLER CALLED")
--   local temp_value = value.value / 100  -- Convert from °C×100
--   log.info(string.format("Max measured temp from device updated: %.2f°C", temp_value))
  
--   -- Store in field
--   device:set_field("maxMeasuredTemp", temp_value, {persist = true})
--   local templog = device:get_field("maxMeasuredTemp")
--   log.info(string.format("Max measured temp from device read: %.2f°C", templog))end

-- ============================================================================
-- REFRESH SETTINGS FUNCTION
-- ============================================================================

local function refresh_settings(device)
  -- log.info("========================================")
  -- log.info("RM3500ZB REFRESHING SETTINGS")
  -- log.info("========================================")
  
  -- Read Low Temperature Protection setting
  device:send(cluster_base.read_manufacturer_specific_attribute(
    device,
    SINOPE_SWITCH_CLUSTER,
    SINOPE_DR_MIN_WATER_TEMP_ATTR,
    0x119C
  ))
  
  -- -- Read Tank Size setting (Connected Load)
  -- device:send(cluster_base.read_manufacturer_specific_attribute(
  --   device,
  --   SINOPE_SWITCH_CLUSTER,
  --   SINOPE_CONNECTED_LOAD_ATTR,
  --   0x119C
  -- ))
  
  -- -- Read Min Measured Temp
  -- device:send(cluster_base.read_manufacturer_specific_attribute(
  --   device,
  --   SINOPE_SWITCH_CLUSTER,
  --   SINOPE_MIN_MEASURED_TEMP_ATTR,
  --   0x119C
  -- ))
  
  -- -- Read Max Measured Temp
  -- device:send(cluster_base.read_manufacturer_specific_attribute(
  --   device,
  --   SINOPE_SWITCH_CLUSTER,
  --   SINOPE_MAX_MEASURED_TEMP_ATTR,
  --   0x119C
  -- ))
end

-- ============================================================================
-- REFRESH ALL VALUES + SETTINGS
-- ============================================================================


local function do_refresh(driver, device)
  -- log.info("========================================")
  -- log.info("RM3500ZB DOREFRESH HANDLER CALLED")
  -- log.info("========================================")
  
  -- Refresh all values
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(SimpleMetering.attributes.InstantaneousDemand:read(device))
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
  device:send(ElectricalMeasurement.attributes.RMSVoltage:read(device))
  device:send(ElectricalMeasurement.attributes.RMSCurrent:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
  device:send(OnOff.attributes.OnOff:read(device))
  
  -- Refresh settings values
  refresh_settings(device) 
end

-- ============================================================================
-- CONFIGURE HANDLER - Set reporting intervals
-- ============================================================================

local function configure_device(driver, device)
  -- log.info("========================================")
  -- log.info("RM3500ZB CONFIGURE DEVICE HANDLER CALLED")
  -- log.info("========================================")

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


  -- Refresh all values + settings
  do_refresh(driver, device)


end

-- ============================================================================
-- PREFERENCES CHANGE HANDLER
-- ============================================================================

local function info_changed_handler(driver, device, event, args)
  -- log.info("========================================")
  -- log.info("RM3500ZB INFO_CHANGED HANDLER CALLED")
  -- log.info("========================================")
  
  -- -- Check if this is a settings page open (no old preferences)
  if not args.old_st_store.preferences then
    -- log.info("Settings page opened - refreshing values")
    refresh_settings(device)
    return
  end

  -- Handle Low Temperature Protection change
  if args.old_st_store.preferences.lowTempProtection ~= device.preferences.lowTempProtection then
    local new_value = tonumber(device.preferences.lowTempProtection)
    -- log.info(string.format("Low temp protection changed to: %d°C", new_value))
    
    -- Write to device
    device:send(cluster_base.write_manufacturer_specific_attribute(
      device,
      SINOPE_SWITCH_CLUSTER,
      SINOPE_DR_MIN_WATER_TEMP_ATTR,
      0x119C,
      data_types.Uint8,
      new_value
    ))
    
    -- Read back after 2 seconds to verify
    device.thread:call_with_delay(2, function()
      log.info("Reading back lowTempProtection after write...")
      device:send(cluster_base.read_manufacturer_specific_attribute(
        device,
        SINOPE_SWITCH_CLUSTER,
        SINOPE_DR_MIN_WATER_TEMP_ATTR,
        0x119C
      ))
    end)
  end
  
  -- -- Handle Tank Size change
  -- if args.old_st_store.preferences.tankSize ~= device.preferences.tankSize then
  --   local new_value = device.preferences.tankSize
  --   log.info(string.format("Tank size changed to: %d Gallons", new_value))
    
  --   -- Write to device
  --   device:send(cluster_base.write_manufacturer_specific_attribute(
  --     device,
  --     SINOPE_SWITCH_CLUSTER,
  --     SINOPE_CONNECTED_LOAD_ATTR,
  --     0x119C,
  --     data_types.Uint16,
  --     new_value
  --   ))
    
  --   -- Read back after 2 seconds to verify
  --   device.thread:call_with_delay(2, function()
  --     log.info("Reading back tankSize after write...")
  --     device:send(cluster_base.read_manufacturer_specific_attribute(
  --       device,
  --       SINOPE_SWITCH_CLUSTER,
  --       SINOPE_CONNECTED_LOAD_ATTR,
  --       0x119C
  --     ))
  --   end)
  -- end
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
    doConfigure = configure_device,
    infoChanged = info_changed_handler,
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
      [SINOPE_SWITCH_CLUSTER] = {
        [SINOPE_DR_MIN_WATER_TEMP_ATTR] = sinope_low_temp_protection_handler,
        -- [SINOPE_MIN_MEASURED_TEMP_ATTR] = sinope_min_measured_temp_handler,
        -- [SINOPE_MAX_MEASURED_TEMP_ATTR] = sinope_max_measured_temp_handler,
      },
    },
  },
  can_handle = require("sinope-waterheater.can_handle")
}


return sinope_rm3500zb



