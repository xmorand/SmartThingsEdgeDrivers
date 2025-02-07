-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local RelativeHumidity = clusters.RelativeHumidity
local Thermostat = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
local ThermostatPower = capabilities.powerMeter

local POWER_ATTTRIBUTE = 0x4008
local MFG_CODE = 0x1185

local RX_FREEZE_VALUE = 0x7ffd
local RX_HEAT_VALUE = 0x7fff
local FREEZE_ALRAM_TEMPERATURE = 0
local HEAT_ALRAM_TEMPERATURE = 50

local STELPRO_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Stelpro", model = "MaestroStat" },
  { mfr = "Stelpro", model = "SORB" },
  { mfr = "Stelpro", model = "SonomaStyle" },
  { mfr = "Stelpro", model = "SMT402AD" } -- added M.Colmenarejo
}

local is_stelpro_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(STELPRO_THERMOSTAT_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local do_refresh = function(self, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.PIHeatingDemand,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode,
    ThermostatUserInterfaceConfiguration.attributes.KeypadLockout,
    RelativeHumidity.attributes.MeasuredValue
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, POWER_ATTTRIBUTE, MFG_CODE))
end

local device_added = function(self, device)
  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
  do_refresh(self, device)
end

local do_configure = function(self, device)
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 10, 60, 50))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 1, 600, 50))
  device:send(Thermostat.attributes.PIHeatingDemand:configure_reporting(device, 1, 60, 1))
  device:send(cluster_base.configure_reporting(device, data_types.ClusterId(Thermostat.ID) , POWER_ATTTRIBUTE, 0x23 , 1, 60, 1))

  device:send(ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(device, 1, 0, 1))
  device:send(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(device, 1, 0, 1))
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 10, 300, 1))

  device:emit_event(ThermostatMode.thermostatMode.heat())
end

local device_init = function(self, device)
  do_configure(self, device)
end

local function get_temperature(temperature)
  return temperature / 100
end

local function thermostat_local_temp_attr_handler(driver, device, value, zb_rx)
  local temperature = value.value
  local temp_scale = "C"
  local event = nil
  if temperature == RX_FREEZE_VALUE then
    event = capabilities.temperatureAlarm.temperatureAlarm.freeze()
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = FREEZE_ALRAM_TEMPERATURE, unit = temp_scale}))
  elseif temperature == RX_HEAT_VALUE then
    event = capabilities.temperatureAlarm.temperatureAlarm.heat()
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = HEAT_ALRAM_TEMPERATURE, unit = temp_scale}))
  else
    temperature = get_temperature(temperature)
    local last_temp = device:get_latest_state("main", capabilities.temperatureMeasurement.ID, capabilities.temperatureMeasurement.temperature.NAME)
    local last_alarm = device:get_latest_state("main", capabilities.temperatureAlarm.ID, capabilities.temperatureAlarm.temperatureAlarm.NAME, "cleared")
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = temperature, unit = temp_scale}))

    if last_alarm ~= "cleared" then
      local clear = false
      if (
        (last_alarm == "freeze" and temperature > FREEZE_ALRAM_TEMPERATURE and last_temp < temperature) or
        (last_alarm == "heat" and temperature < HEAT_ALRAM_TEMPERATURE and last_temp > temperature)
      ) then
        event = capabilities.temperatureAlarm.temperatureAlarm.cleared()
        clear = true
      end
      if clear == false and (
        (last_alarm == "freeze" and temperature > FREEZE_ALRAM_TEMPERATURE) or
        (last_alarm == "heat" and temperature < HEAT_ALRAM_TEMPERATURE)
      ) then
            if last_alarm == "freeze" then
              event = capabilities.temperatureAlarm.temperatureAlarm.freeze()
            else
              event = capabilities.temperatureAlarm.temperatureAlarm.heat()
            end
      end
    else
      if temperature <= FREEZE_ALRAM_TEMPERATURE then
        event = capabilities.temperatureAlarm.temperatureAlarm.freeze()
      elseif temperature >= HEAT_ALRAM_TEMPERATURE then
        event = capabilities.temperatureAlarm.temperatureAlarm.heat()
      end
    end
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local function thermostat_heating_set_point_attr_handler(driver, device, value, zb_rx)
  local point_value = value.value
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = get_temperature(point_value), unit = "C"}))
end

local function thermostat_heating_demand_attr_handler(driver, device, value, zb_rx)
  local event = value.value < 1 and ThermostatOperatingState.thermostatOperatingState.idle() or
                 ThermostatOperatingState.thermostatOperatingState.heating()             
  device:emit_event(event)
end

local function thermostat_power_attr_handler(driver, device, zb_rx)
  local point_value = zb_rx.value
  device:emit_event(capabilities.powerMeter.power({value = point_value, unit = "W"}))
end

local function info_changed(driver, device, event, args)
  if device.preferences ~= nil and device.preferences.lock ~= args.old_st_store.preferences.lock then
    device:send(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:write(device, tonumber(device.preferences.lock)))
  end
end

local device_added = function(self, device)
  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
end

local stelpro_thermostat = {
  NAME = "Stelpro Thermostat Handler",
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.PIHeatingDemand.ID] = thermostat_heating_demand_attr_handler,
        [Thermostat.attributes.LocalTemperature.ID] = thermostat_local_temp_attr_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_set_point_attr_handler,
        [POWER_ATTTRIBUTE] = thermostat_power_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    added = device_added,
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = is_stelpro_thermostat,
}

return stelpro_thermostat
