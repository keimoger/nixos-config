-- Adds kinetic/inertial scrolling to mouse wheel input. A physical wheel's
-- detents (REL_WHEEL) are a fixed size no matter how fast you spin it, so
-- "how hard was it flicked" has to come from the time *between* detents,
-- not the size of any one event -- that's what estimates velocity below.
-- After the real events stop, we keep synthesizing decaying scroll events
-- (a "coast") until the estimated velocity drops under a threshold, so a
-- fast flick travels much further than a single slow notch.
--
-- Lives at /etc/libinput/plugins/50-scroll-inertia.lua. Only one shared
-- timer exists per plugin (libinput:timer_set_relative is global, not
-- per-device), so state for every device is kept in one table and the
-- timer tick walks all of them, rescheduling itself only while at least
-- one device still has active momentum.

version = libinput:register({ 1 })

-- ---- tuning -----------------------------------------------------------
local TICK_US = 16000 -- ~60Hz while coasting
local DECAY = 0.6 -- per-tick velocity multiplier; higher = coasts longer
local STOP_THRESHOLD = 4 -- hi-res units/tick; below this, stop coasting
local MAX_VELOCITY = 600 -- hi-res units/tick; clamp so a very fast spin
-- doesn't produce an unreasonably long coast
local MAX_EVENT_GAP_US = 250000 -- ignore gaps longer than this (e.g. the
-- first notch after a long pause) when
-- estimating velocity from inter-event timing
local HIRES_PER_NOTCH = 120 -- standard hi-res-to-legacy-notch ratio
local MIN_VELOCITY_TO_COAST = 60 -- hi-res units/tick; below this (or when
-- there's no reliable timing at all, e.g. an
-- isolated click after being idle), don't
-- coast -- requires two notches under ~32ms
-- apart, a real flick, not a single click
-- ------------------------------------------------------------------------

local devices = {}

local function state_for(device)
	local st = devices[device]
	if not st then
		st = { v = 0, active = false, hires_accum = 0, last_ts = nil }
		devices[device] = st
	end
	return st
end

local function any_active()
	for _, st in pairs(devices) do
		if st.active then
			return true
		end
	end
	return false
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function inject_scroll(device, st, hires_delta)
	if hires_delta == 0 then
		return
	end
	st.hires_accum = st.hires_accum + hires_delta
	local frame = {
		{ usage = evdev.REL_WHEEL_HI_RES, value = math.floor(hires_delta) },
	}
	while math.abs(st.hires_accum) >= HIRES_PER_NOTCH do
		local sign = st.hires_accum > 0 and 1 or -1
		table.insert(frame, { usage = evdev.REL_WHEEL, value = sign })
		st.hires_accum = st.hires_accum - sign * HIRES_PER_NOTCH
	end
	device:append_frame(frame)
end

libinput:connect("timer-expired", function(now)
	for device, st in pairs(devices) do
		if st.active then
			st.v = st.v * DECAY
			if math.abs(st.v) < STOP_THRESHOLD then
				st.active = false
				st.v = 0
				st.hires_accum = 0
			else
				inject_scroll(device, st, st.v)
			end
		end
	end
	if any_active() then
		libinput:timer_set_relative(TICK_US)
	end
end)

libinput:connect("new-evdev-device", function(device)
	local st = state_for(device)

	device:connect("evdev-frame", function(dev, frame, timestamp)
		for _, ev in ipairs(frame) do
			if ev.usage == evdev.REL_WHEEL_HI_RES then
				-- Only a valid dt (a *previous* real event close enough
				-- in time) counts as evidence of a flick. No prior
				-- event, or too long since one, means we genuinely
				-- don't know the speed -- treat as a deliberate single
				-- click and don't coast, rather than guessing "fast"
				-- from the fallback of just this one event's own size
				-- (every notch is the same size regardless of speed,
				-- see top of file).
				local scaled = nil
				if st.last_ts then
					local dt = timestamp - st.last_ts
					if dt > 0 and dt < MAX_EVENT_GAP_US then
						scaled = (ev.value / dt) * TICK_US
					end
				end
				st.last_ts = timestamp

				if scaled and math.abs(scaled) > MIN_VELOCITY_TO_COAST then
					st.v = clamp(scaled, -MAX_VELOCITY, MAX_VELOCITY)
					st.active = true
					st.hires_accum = 0
					libinput:timer_set_relative(TICK_US)
				else
					st.active = false
				end
			end
		end
		return nil -- pass the real event through unmodified
	end)

	device:connect("device-removed", function(dev)
		devices[dev] = nil
	end)
end)
