-- Kinetic scrolling for physical mouse/trackball wheels.
--
-- This deliberately does not synthesize touchpad contacts. libinput Lua
-- plugins run before touchpad gesture recognition, so fabricating contacts
-- after a lift can be mistaken for real fingers and cause phantom touches.
-- Touchpads therefore keep libinput's native two-finger scrolling behavior.

version = libinput:register({ 1 })

local TICK_US = 16000
local DECAY = 0.88
local MAX_EVENT_GAP_US = 250000
local MIN_VELOCITY = 55
local STOP_THRESHOLD = 3
local MAX_VELOCITY = 900

local devices = {}
local timer_running = false

local function state_for(device)
    local state = devices[device]
    if not state then
        state = {
            last_ts = nil,
            velocity_y = 0,
            velocity_x = 0,
            coast_y = false,
            coast_x = false,
            remainder_y = 0,
            remainder_x = 0,
        }
        devices[device] = state
    end
    return state
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function trunc(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end

local function start_timer()
    if not timer_running then
        timer_running = true
        libinput:timer_set_relative(TICK_US)
    end
end

local function any_coasting()
    for _, state in pairs(devices) do
        if state.coast_y or state.coast_x then return true end
    end
    return false
end

local function append_wheel(device, state, axis, amount)
    local remainder_name = axis == "y" and "remainder_y" or "remainder_x"
    state[remainder_name] = state[remainder_name] + amount

    local hires = trunc(state[remainder_name])
    if hires == 0 then return end
    state[remainder_name] = state[remainder_name] - hires

    local frame = {}
    if axis == "y" then
        table.insert(frame, { usage = evdev.REL_WHEEL_HI_RES, value = hires })
    else
        table.insert(frame, { usage = evdev.REL_HWHEEL_HI_RES, value = hires })
    end

    device:append_frame(frame)
end

libinput:connect("timer-expired", function()
    timer_running = false

    for device, state in pairs(devices) do
        if state.coast_y then
            state.velocity_y = state.velocity_y * DECAY
            if math.abs(state.velocity_y) <= STOP_THRESHOLD then
                state.velocity_y = 0
                state.coast_y = false
                state.remainder_y = 0
            else
                append_wheel(device, state, "y", state.velocity_y)
            end
        end

        if state.coast_x then
            state.velocity_x = state.velocity_x * DECAY
            if math.abs(state.velocity_x) <= STOP_THRESHOLD then
                state.velocity_x = 0
                state.coast_x = false
                state.remainder_x = 0
            else
                append_wheel(device, state, "x", state.velocity_x)
            end
        end
    end

    if any_coasting() then start_timer() end
end)

libinput:connect("new-evdev-device", function(device)
    local state = state_for(device)

    device:connect("evdev-frame", function(_, frame, timestamp)
        for _, event in ipairs(frame) do
            local axis = nil
            if event.usage == evdev.REL_WHEEL_HI_RES then
                axis = "y"
            elseif event.usage == evdev.REL_HWHEEL_HI_RES then
                axis = "x"
            end

            if axis then
                local previous = state.last_ts
                local dt = previous and (timestamp - previous) or nil
                state.last_ts = timestamp

                if dt and dt > 0 and dt < MAX_EVENT_GAP_US then
                    local velocity = clamp((event.value / dt) * TICK_US,
                        -MAX_VELOCITY, MAX_VELOCITY)
                    if axis == "y" then
                        state.velocity_y = velocity
                        state.coast_y = math.abs(velocity) >= MIN_VELOCITY
                    else
                        state.velocity_x = velocity
                        state.coast_x = math.abs(velocity) >= MIN_VELOCITY
                    end
                    if math.abs(velocity) >= MIN_VELOCITY then start_timer() end
                else
                    -- An isolated detent is intentional scrolling, not a flick.
                    if axis == "y" then
                        state.velocity_y = 0
                        state.coast_y = false
                    else
                        state.velocity_x = 0
                        state.coast_x = false
                    end
                end
            end
        end
        return nil
    end)

    device:connect("device-removed", function(removed)
        devices[removed] = nil
    end)
end)
