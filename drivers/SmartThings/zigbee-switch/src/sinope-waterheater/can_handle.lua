-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "Sinope Technologies" and device:get_model() == "RM3500ZB"
    if can_handle then
      local subdriver = require("sinope-waterheater")
      return true, subdriver
    else
      return false
    end
  end
