-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local SINOPE_SWITCH_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053

-- RM3500ZB additional manufacturer attributes (0xFF01)[web:45]
local SINOPE_CONNECTED_LOAD_ATTR          = 0x0060  -- ConnectedLoad (W)[web:45]
local SINOPE_CURRENT_LOAD_ATTR            = 0x0070  -- CurrentLoad (W-ish bitmap)[web:45]
local SINOPE_DR_MIN_WATER_TEMP_ATTR       = 0x0076  -- drConfigWaterTempMin (°C)[web:45]
local SINOPE_DR_MIN_WATER_TEMP_TIME_ATTR  = 0x0077  -- drConfigWaterTempTime[web:45]
local SINOPE_TIMER_ATTR                   = 0x00A0  -- Timer seconds[web:45]
local SINOPE_TIMER_COUNTDOWN_ATTR         = 0x00A1  -- Timer_countDown[web:45]
local SINOPE_MIN_MEASURED_TEMP_ATTR       = 0x007C  -- min_measured_temp (°C×100)[web:45]
local SINOPE_MAX_MEASURED_TEMP_ATTR       = 0x007D  -- max_measured_temp (°C×100)[web:45]
local SINOPE_ENERGY_INTERNAL_ATTR         = 0x0090  -- currentSummationDelivered (internal)[web:45]

local OnOff                 = clusters.OnOff          -- 0x0006
local TempMeas              = clusters.TemperatureMeasurement -- 0x0402
local IASZone               = clusters.IASZone        -- 0x0500
local ElectricalMeasurement = clusters.ElectricalMeasurement   -- 0x0B04
local Metering              = clusters.Metering       -- 0x0702



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

local zigbee_sinope_switch = {
  NAME = "Zigbee Sinope switch",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  
  zigbee_handlers = {
    attr = {
      -- Standard clusters used by RM3500ZB[web:41][web:45]
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
        [ElectricalMeasurement.attributes.ActivePower.ID] = active_power_attr_handler
      },
      [Metering.ID] = {
        [Metering.attributes.CurrentSummationDelivered.ID] = energy_attr_handler
      },

      -- Optional: manufacturer-specific 0xFF01 attributes for RM3500ZB[web:45]
      [SINOPE_SWITCH_CLUSTER] = {
        [SINOPE_CONNECTED_LOAD_ATTR]    = sinope_connected_load_handler,
        [SINOPE_MIN_MEASURED_TEMP_ATTR] = sinope_min_temp_handler,
        [SINOPE_MAX_MEASURED_TEMP_ATTR] = sinope_max_temp_handler,
        -- add more as needed (Timer, DR min temp, etc.)
      }
    }
  },

  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME]  = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler,
    -- Add mappings for any custom capabilities you define for DR/timer/load here
    }
  },
  can_handle = require("sinope.can_handle"),
}

return zigbee_sinope_switch

-- Switch on/off from 0x0006/0x0000[web:45]
local function onoff_attr_handler(driver, device, value, zb_rx)
  if value.value then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

-- Water temperature from 0x0402/0x0000 (°C×100)[web:45]
local function water_temp_attr_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = temp_c, unit = "C" }))
end

-- Leak state from IAS Zone 0x0500/0x0002[web:45]
local function leak_attr_handler(driver, device, value, zb_rx)
  local zone_status = value.value
  local wet = (bit32.band(zone_status, 0x0001) ~= 0)  -- example mask
  if wet then
    device:emit_event(capabilities.waterSensor.water.wet())
  else
    device:emit_event(capabilities.waterSensor.water.dry())
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

local function sinope_min_temp_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  -- device:emit_event(capabilities["yourNamespace.minTankTemp"].temperature({ value = temp_c, unit = "C" }))
end

local function sinope_max_temp_handler(driver, device, value, zb_rx)
  local temp_c = value.value / 100.0
  -- device:emit_event(capabilities["yourNamespace.maxTankTemp"].temperature({ value = temp_c, unit = "C" }))
end


