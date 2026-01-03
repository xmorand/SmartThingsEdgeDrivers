-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"

-- Sinopé manufacturer cluster and attributes
local SINOPE_SWITCH_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053
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
local OnOff                 = clusters.OnOff          -- 0x0006
local TempMeas              = clusters.TemperatureMeasurement -- 0x0402
local IASZone               = clusters.IASZone        -- 0x0500
local ElectricalMeasurement = clusters.ElectricalMeasurement   -- 0x0B04
local Metering              = clusters.Metering       -- 0x0702
local Thermostat = clusters.Thermostat


-- Switch on/off from 0x0006/0x0000
local function onoff_attr_handler(driver, device, value, zb_rx)
  if value.value then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

-- Water temperature from cluster 0x0402, attribute 0x0000 (°C×100)
local function water_temp_attr_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  device:emit_event(capabilities.temperatureMeasurement.temperature({
    value = temp_c, 
    unit = "C"
  }))
end

-- Leak state from IAS Zone 0x0500/0x0002[web:45]
local function leak_attr_handler(driver, device, value, zb_rx)
  local zone_status = value.value
  local wet = (bit32.band(zone_status, 0x0001) ~= 0)  -- example mask
  if wet then
    device:emit_event(capabilities.waterLeak.water.wet())
  else
    device:emit_event(capabilities.waterLeak.water.dry())
  end
end

-- Active power from 0x0B04/0x050B[web:45]
local function active_power_attr_handler(driver, device, value, zb_rx)
  local power_w = value.value  -- apply multiplier/divisor if needed
  device:emit_event(capabilities.powerMeter.power({ value = power_w, unit = "W" }))
end

-- Energy from 0x0702/0x0000 (Wh or kWh with multiplier/divisor)[web:41][web:45]
local function energy_attr_handler(driver, device, value, zb_rx)
  local raw = value.value
  -- If you read AC Power Multiplier/Divisor, apply here; otherwise assume Wh and convert
  local kwh = raw / 1000.0
  device:emit_event(capabilities.energyMeter.energy({ value = kwh, unit = "kWh" }))
  
end

-- Voltage from Electrical Measurement cluster 0x0B04, attribute 0x0505
local function voltage_attr_handler(driver, device, value, zb_rx)
  local voltage_raw = value.value
  -- Device sends in 0.1V increments
  local voltage_v = math.floor((voltage_raw / 10) + 0.5)
  device:emit_event(capabilities.voltageMeasurement.voltage({
    value = voltage_v, 
    unit = "V"
  }))
end

-- Current from Electrical Measurement cluster 0x0B04, attribute 0x0508
local function current_attr_handler(driver, device, value, zb_rx)
  local current_raw = value.value
  -- Device sends in 0.001A (1mA) increments
  local current_a = math.floor((current_raw / 1000) + 0.5)
  device:emit_event(capabilities.currentMeter.current({
    value = current_a, 
    unit = "A"
  }))
end

-- Cooling setpoint from Thermostat cluster 0x0201, attribute 0x0012
local function cooling_setpoint_attr_handler(driver, device, value, zb_rx)
  local setpoint_raw = value.value or 4600  -- Default 46°C
  local setpoint_c = setpoint_raw / 100
  device:emit_event(capabilities.thermostatCoolingSetpoint.coolingSetpoint({
    value = math.floor(setpoint_c + 0.5), 
    unit = "C"
  }))
end

-- Manufacturer-specific: Connected load
local function sinope_connected_load_handler(driver, device, value, zb_rx)
  local load_w = value.value
  -- You could store this or emit a custom capability event
  device:set_field("connected_load", load_w, {persist = true})
end

local function sinope_min_temp_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  -- device:emit_event(capabilities["yourNamespace.minTankTemp"].temperature({ value = temp_c, unit = "C" }))
  -- device:set_field("min_measured_temp", temp_c, {persist = true})
end

local function sinope_max_temp_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  -- device:emit_event(capabilities["yourNamespace.maxTankTemp"].temperature({ value = temp_c, unit = "C" }))
  -- device:set_field("max_measured_temp", temp_c, {persist = true})
end
-- =============================================================================
-- COMMAND HANDLERS
-- =============================================================================

-- Handle switch.on command
local function switch_on_handler(driver, device, command)
  device:send(OnOff.server.commands.On(device))
end

-- Handle switch.off command
local function switch_off_handler(driver, device, command)
  device:send(OnOff.server.commands.Off(device))
end

-- Handle thermostatCoolingSetpoint.setCoolingSetpoint command
local function set_cooling_setpoint_handler(driver, device, command)
  local setpoint_c = command.args.setpoint or 46
  
  -- Validate range (RM3500ZB supports 46-55°C)
  if setpoint_c < 46 then setpoint_c = 46 end
  if setpoint_c > 55 then setpoint_c = 55 end
  
  local zigbee_value = setpoint_c * 100
  
  -- Get current setpoint to calculate delta
  local current_setpoint = device:get_field("current_cooling_setpoint") or (46 * 100)
  local delta = zigbee_value - current_setpoint
  
  device:send(Thermostat.server.commands.SetpointRaiseLower(device, 0x02, delta))
  device:set_field("current_cooling_setpoint", zigbee_value, {persist = true})
end

-- Handle refresh command
local function refresh_handler(driver, device, command)
  -- Read all important attributes
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(TempMeas.attributes.MeasuredValue:read(device))
  device:send(Metering.attributes.InstantaneousDemand:read(device))
  device:send(Metering.attributes.CurrentSummationDelivered:read(device))
  device:send(ElectricalMeasurement.attributes.RMSVoltage:read(device))
  device:send(ElectricalMeasurement.attributes.RMSCurrent:read(device))
  device:send(Thermostat.attributes.CoolingSetpoint:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
end

-- =============================================================================
-- PREFERENCE CHANGE HANDLER
-- =============================================================================

local function info_changed(driver, device, event, args)
  -- handle ledIntensity preference setting
  if (args.old_st_store.preferences.ledIntensity ~= device.preferences.ledIntensity) then
    local ledIntensity = device.preferences.ledIntensity

    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
  end
  -- Example: DR minimum water temperature preference
  if args.old_st_store.preferences.drMinWaterTemp ~= device.preferences.drMinWaterTemp then
    local minTemp = device.preferences.drMinWaterTemp  -- in °C
    device:send(cluster_base.write_attribute(
      device,
      data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
      data_types.AttributeId(SINOPE_DR_MIN_WATER_TEMP_ATTR),
      data_types.validate_or_build_type(minTemp, data_types.Uint8, "payload")
    ))
  end
end

-- =============================================================================
-- DRIVER DEFINITION (NOW handlers are defined above and can be referenced)
-- =============================================================================

local zigbee_sinope_switch = {
  NAME = "Zigbee Sinope switch",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  
  zigbee_handlers = {
    attr = {
      -- Standard clusters used by RM3500ZB
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_attr_handler
      },
      [TempMeas.ID] = {
        [TempMeas.attributes.MeasuredValue.ID] = water_temp_attr_handler
      },
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = leak_attr_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.RMSVoltage.ID] = voltage_attr_handler,
        [ElectricalMeasurement.attributes.RMSCurrent.ID] = current_attr_handler,
      },
      [Metering.ID] = {
        [Metering.attributes.InstantaneousDemand.ID] = power_attr_handler,
        [Metering.attributes.CurrentSummationDelivered.ID] = energy_attr_handler,
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.CoolingSetpoint.ID] = cooling_setpoint_attr_handler,
      },

      -- Optional: manufacturer-specific 0xFF01 attributes for RM3500ZB[web:45]
      [SINOPE_SWITCH_CLUSTER] = {
        [SINOPE_CONNECTED_LOAD_ATTR] = sinope_connected_load_handler,
        [SINOPE_MIN_MEASURED_TEMP_ATTR] = sinope_min_temp_handler,
        [SINOPE_MAX_MEASURED_TEMP_ATTR] = sinope_max_temp_handler,
        -- add more as needed (Timer, DR min temp, etc.)
      }
    }
  },

  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler,
    -- Add mappings for any custom capabilities you define for DR/timer/load here
  },
  [capabilities.thermostatCoolingSetpoint.ID] = {
    [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] = set_cooling_setpoint_handler,
  },
  [capabilities.refresh.ID] = {
    [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
  },
},
  can_handle = require("sinope.can_handle"),
}

return zigbee_sinope_switch