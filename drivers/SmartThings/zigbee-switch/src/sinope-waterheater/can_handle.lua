-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function can_handle_sinope_rm3500zb(opts, driver, device, ...)
  if device ~= nil then
    local manufacturer = device:get_manufacturer()
    local model = device:get_model()
    
    -- Check if this is an RM3500ZB
    return manufacturer == "Sinope Technologies" and model == "RM3500ZB"
  end
  
  return false
end

return can_handle_sinope_rm3500zb