-- Adds kinetic/inertial scrolling to mouse wheel input AND touchpad
-- two-finger scrolling.
--
-- Mouse wheel: a physical wheel's detents (REL_WHEEL) are a fixed size no
-- matter how fast you spin it, so "how hard was it flicked" has to come
-- from the time *between* detents, not the size of any one event -- that's
-- what estimates velocity below. The coast itself works by injecting
-- synthetic REL_WHEEL/REL_WHEEL_HI_RES events, because libinput dispatches
-- a mouse device through its relative-pointer interface, which genuinely
-- understands those event codes.
--
-- Touchpad: the libinput Lua plugin API only ever sees raw evdev data from
-- *before* libinput's own gesture/scroll recognition runs (confirmed
-- directly in libinput's own doc/user/lua-plugins.rst -- there is no
-- higher-level "this was a scroll" event exposed to plugins at all), so
-- there's no way to hook "the real two-finger scroll libinput already
-- produces" after the fact. The real, in-progress two-finger scroll is
-- left completely alone here (it already feels fine on its own) -- this
-- only watches raw two-finger touch movement purely to estimate how fast
-- it was moving *at the moment the fingers lift*.
--
-- Critically, the coast that follows a touchpad lift can NOT reuse the
-- wheel path's REL_WHEEL injection trick, even though an earlier version
-- of this file tried exactly that. Confirmed directly against libinput's
-- own source (src/evdev-mt-touchpad.c, tp_process_state()): a device
-- libinput has classified as a touchpad is dispatched through a
-- completely different interface than a mouse, one that only ever reads
-- EV_ABS/EV_KEY/EV_MSC events -- there is no EV_REL handling anywhere in
-- that path. Injecting REL_WHEEL onto a touchpad device is silently
-- swallowed: libinput_device_dispatch_frame() delivers it exactly as
-- designed, and the touchpad's own dispatch function then just never
-- looks at it. This was confirmed live: a `libinput debug-events`
-- capture during real flicks showed the lift-off velocity being computed
-- correctly every time, yet not one POINTER_SCROLL_WHEEL event was ever
-- produced by it, on any application.
--
-- So instead, the coast here fakes *continued finger movement*: once a
-- real two-finger lift is detected with enough velocity, this starts
-- synthesizing new ABS_MT_SLOT/ABS_MT_TRACKING_ID/ABS_MT_POSITION_X/Y
-- events for two touches (reusing the just-freed slot numbers, but with
-- fresh tracking IDs so libinput sees them as new contacts rather than a
-- resumed one -- the real contacts already sent their own TRACKING_ID=-1
-- and libinput has already ended that gesture by the time this reacts),
-- decaying the Y delta each tick, until velocity drops under a threshold,
-- at which point both fake touches get their own TRACKING_ID=-1 to end
-- cleanly. libinput's own (already-correct) touchpad gesture recognition
-- does the rest, exactly as it would for a real, slowing-down drag --
-- this never has to reimplement touch-to-scroll conversion itself.
--
-- After the real events (or real finger contact) stop, we keep
-- synthesizing decaying events (a "coast") until the estimated velocity
-- drops under a threshold, so a fast flick travels much further than a
-- single slow notch or a short drag.
--
-- Lives at /etc/libinput/plugins/50-scroll-inertia.lua. Only one shared
-- timer exists per plugin (libinput:timer_set_relative is global, not
-- per-device), so state for every device is kept in one table and the
-- timer tick walks all of them, rescheduling itself only while at least
-- one device still has active momentum (wheel coast or touchpad coast).

version = libinput:register({ 1 })

-- ---- tuning -----------------------------------------------------------
local TICK_US = 16000 -- ~60Hz while coasting
local DECAY = 0.6 -- per-tick velocity multiplier; higher = coasts longer
local MAX_EVENT_GAP_US = 250000 -- ignore gaps longer than this (e.g. the
-- first notch after a long pause) when
-- estimating velocity from inter-event timing
local TOUCHPAD_RESOLUTION_FALLBACK = 12 -- units/mm, used only if a device
-- somehow doesn't report a real
-- ABS_MT_POSITION_Y resolution

-- Wheel coast, in hi-res wheel units/tick (120 hi-res units = 1 notch).
local STOP_THRESHOLD = 4
local MAX_VELOCITY = 600
local HIRES_PER_NOTCH = 120
local MIN_VELOCITY_TO_COAST = 60 -- below this (or when there's no reliable
-- timing at all, e.g. an isolated click after
-- being idle), don't coast -- requires two
-- notches under ~32ms apart, a real flick

-- Touchpad coast, in real mm/tick -- a physically meaningful unit, unlike
-- the wheel path's hi-res units, since this feeds directly into a
-- position delta rather than a wheel-notch count.
local TOUCHPAD_DECAY = 0.85 -- deliberately its own, gentler constant,
-- not the shared wheel DECAY (0.6) above.
-- Confirmed live (debug logging of the raw
-- pre-clamp lift velocity): real flicks were
-- landing around 3-9 mm/tick, nowhere near
-- TOUCHPAD_MAX_VELOCITY_MM's old 12 clamp --
-- ruling that out as the cause of a previous
-- "does a lil flick and stops again, not
-- smooth" complaint. At 0.6 decay, even a
-- genuinely fast ~9 mm/tick flick dies out in
-- ~10 ticks (~160ms) -- too short to read as a
-- glide at all, which is what that complaint
-- actually was. 0.85 stretches the same flick
-- to ~30+ ticks (~500ms+), long enough to
-- register as a real coast; retune by feel from
-- here rather than trusting this exact number.
local TOUCHPAD_MIN_VELOCITY_TO_COAST_MM = 0.5 -- below this, treat as a
-- deliberate slow drag, not a flick
local TOUCHPAD_MAX_VELOCITY_MM = 12 -- clamp so a very fast flick doesn't
-- produce an unreasonably long coast
local TOUCHPAD_STOP_THRESHOLD_MM = 0.05 -- below this, end the fake touch

-- Plausible finger-sized contact values for the fake touches, sent once
-- when each one starts. Real touch data includes these alongside
-- position; the first version of this coast omitted them entirely
-- (leaving them at libinput's internal default for a brand-new touch --
-- effectively 0/unset), and while libinput's own raw axis recognition
-- didn't seem to care (confirmed via `libinput debug-events`: the coast
-- showed up there just fine), no scroll ever reached actual Wayland
-- clients (confirmed via `wev`: real flicks' stops were always instant,
-- never a single decaying tail across ~20 samples) -- consistent with
-- KWin (or a higher gesture-validity check feeding it) filtering out
-- zero-size contacts as noise/palm-like before forwarding. Values below
-- are plausible fingertip-sized numbers scaled off this exact device's
-- own advertised ranges (confirmed via evtest: TOUCH_MAJOR/MINOR max
-- 1020, PRESSURE max 253), not measured from a real touch -- the exact
-- numbers likely don't matter much, just that they're nonzero and
-- finger-plausible rather than absent.
local TOUCHPAD_FAKE_TOUCH_MAJOR = 300
local TOUCHPAD_FAKE_TOUCH_MINOR = 250
local TOUCHPAD_FAKE_PRESSURE = 100
-- ------------------------------------------------------------------------

local devices = {}

local function state_for(device)
	local st = devices[device]
	if not st then
		st = {
			-- Wheel coast state.
			v = 0,
			active = false,
			hires_accum = 0,
			last_ts = nil,

			-- Touchpad two-finger tracking, independent of the wheel
			-- fields above.
			tp_resolution = nil, -- ABS_MT_POSITION_Y units/mm, cached on connect
			tp_position_min_y = nil,
			tp_position_max_y = nil,
			tp_tracking_id_max = nil,
			tp_next_tracking_id = nil,
			tp_current_slot = 0, -- MT protocol: slot 0 is implicit until an
			-- ABS_MT_SLOT event says otherwise, so this
			-- must default to 0, not nil -- using nil as
			-- a table key below would be a hard error,
			-- not a harmless no-op.
			tp_slot_x = {}, -- per-slot last known raw X, keyed by slot number.
			tp_slot_y = {}, -- per-slot last known raw Y. Both persist across a
			-- lift (never cleared on TRACKING_ID=-1) so the
			-- coast below has a real last-known position to
			-- start from -- only tp_active_slots tracks
			-- whether a slot is *currently* touching.
			tp_active_slots = {}, -- set of currently-touching slot numbers
			tp_active_count = 0,
			tp_last_avg_y = nil,
			tp_last_sample_ts = nil,
			tp_last_velocity = nil, -- most recent mm/tick estimate

			-- Touchpad coast state (the synthesized post-lift "still
			-- moving" touches).
			tp_coasting = false,
			tp_coast_first_tick = false, -- next tick must also send
			-- TRACKING_ID + POSITION_X to
			-- "start" the fake touches
			tp_coast_v = 0,
			tp_coast_slot_a = nil,
			tp_coast_slot_b = nil,
			tp_coast_id_a = nil,
			tp_coast_id_b = nil,
			tp_coast_x_a = nil,
			tp_coast_x_b = nil,
			tp_coast_y_a = nil,
			tp_coast_y_b = nil,
		}
		devices[device] = st
	end
	return st
end

-- Average raw Y across exactly the tracked two active slots, or nil if
-- fewer/more than two are down or either slot's Y hasn't been seen yet
-- (e.g. the very first frame or two right after both fingers land).
local function tp_avg_active_y(st)
	if st.tp_active_count ~= 2 then
		return nil
	end
	local sum, n = 0, 0
	for slot in pairs(st.tp_active_slots) do
		local y = st.tp_slot_y[slot]
		if y == nil then
			return nil
		end
		sum = sum + y
		n = n + 1
	end
	if n ~= 2 then
		return nil
	end
	return sum / 2
end

local function any_active()
	for _, st in pairs(devices) do
		if st.active or st.tp_coasting then
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

-- Allocates the next synthetic tracking ID for this device, wrapping
-- around within the device's own advertised range (starting from its
-- midpoint) so these never collide with the real, kernel-assigned IDs a
-- device normally hands out from 0 upward.
local function tp_next_tracking_id(st)
	st.tp_next_tracking_id = st.tp_next_tracking_id + 1
	if st.tp_next_tracking_id > st.tp_tracking_id_max then
		st.tp_next_tracking_id = math.floor(st.tp_tracking_id_max / 2)
	end
	return st.tp_next_tracking_id
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

-- Advances the touchpad coast by one tick: decays velocity, moves both
-- fake touches by the resulting delta (converted from mm to this
-- device's own raw units via its resolution), and ends them cleanly once
-- velocity drops under the stop threshold.
local function tp_coast_tick(device, st)
	-- Skip the decay on this coast's very first tick. Decaying
	-- unconditionally on every tick (including the first) meant the
	-- synthetic motion started at DECAY (60%) of the real lift-off
	-- speed instead of continuing at it -- a sudden speed drop right
	-- at the real-to-synthetic handoff, not a gradual one, which is
	-- exactly what felt "torn"/discontinuous rather than smooth when
	-- tested live.
	if not st.tp_coast_first_tick then
		st.tp_coast_v = st.tp_coast_v * TOUCHPAD_DECAY
	end

	if math.abs(st.tp_coast_v) < TOUCHPAD_STOP_THRESHOLD_MM then
		device:append_frame({
			{ usage = evdev.ABS_MT_SLOT, value = st.tp_coast_slot_a },
			{ usage = evdev.ABS_MT_TRACKING_ID, value = -1 },
			{ usage = evdev.ABS_MT_SLOT, value = st.tp_coast_slot_b },
			{ usage = evdev.ABS_MT_TRACKING_ID, value = -1 },
		})
		st.tp_coasting = false
		return
	end

	local delta_units = st.tp_coast_v * st.tp_resolution
	st.tp_coast_y_a = clamp(st.tp_coast_y_a + delta_units, st.tp_position_min_y, st.tp_position_max_y)
	st.tp_coast_y_b = clamp(st.tp_coast_y_b + delta_units, st.tp_position_min_y, st.tp_position_max_y)

	local frame = {}

	table.insert(frame, { usage = evdev.ABS_MT_SLOT, value = st.tp_coast_slot_a })
	if st.tp_coast_first_tick then
		table.insert(frame, { usage = evdev.ABS_MT_TRACKING_ID, value = st.tp_coast_id_a })
		table.insert(frame, { usage = evdev.ABS_MT_POSITION_X, value = math.floor(st.tp_coast_x_a) })
		table.insert(frame, { usage = evdev.ABS_MT_TOUCH_MAJOR, value = TOUCHPAD_FAKE_TOUCH_MAJOR })
		table.insert(frame, { usage = evdev.ABS_MT_TOUCH_MINOR, value = TOUCHPAD_FAKE_TOUCH_MINOR })
		table.insert(frame, { usage = evdev.ABS_MT_PRESSURE, value = TOUCHPAD_FAKE_PRESSURE })
	end
	table.insert(frame, { usage = evdev.ABS_MT_POSITION_Y, value = math.floor(st.tp_coast_y_a) })

	table.insert(frame, { usage = evdev.ABS_MT_SLOT, value = st.tp_coast_slot_b })
	if st.tp_coast_first_tick then
		table.insert(frame, { usage = evdev.ABS_MT_TRACKING_ID, value = st.tp_coast_id_b })
		table.insert(frame, { usage = evdev.ABS_MT_POSITION_X, value = math.floor(st.tp_coast_x_b) })
		table.insert(frame, { usage = evdev.ABS_MT_TOUCH_MAJOR, value = TOUCHPAD_FAKE_TOUCH_MAJOR })
		table.insert(frame, { usage = evdev.ABS_MT_TOUCH_MINOR, value = TOUCHPAD_FAKE_TOUCH_MINOR })
		table.insert(frame, { usage = evdev.ABS_MT_PRESSURE, value = TOUCHPAD_FAKE_PRESSURE })
	end
	table.insert(frame, { usage = evdev.ABS_MT_POSITION_Y, value = math.floor(st.tp_coast_y_b) })

	device:append_frame(frame)
	st.tp_coast_first_tick = false
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
		if st.tp_coasting then
			tp_coast_tick(device, st)
		end
	end
	if any_active() then
		libinput:timer_set_relative(TICK_US)
	end
end)

libinput:connect("new-evdev-device", function(device)
	local st = state_for(device)

	-- Only touchpads have this axis at all; devices without it (e.g. a
	-- plain mouse) just never populate tp_resolution, and the
	-- `if st.tp_resolution then` guard below keeps the touchpad path a
	-- no-op for them regardless.
	local absinfos = device:absinfos()
	if absinfos and absinfos[evdev.ABS_MT_POSITION_Y] then
		local y_info = absinfos[evdev.ABS_MT_POSITION_Y]
		st.tp_resolution = y_info.resolution
		if not st.tp_resolution or st.tp_resolution <= 0 then
			st.tp_resolution = TOUCHPAD_RESOLUTION_FALLBACK
		end
		st.tp_position_min_y = y_info.minimum
		st.tp_position_max_y = y_info.maximum

		local id_info = absinfos[evdev.ABS_MT_TRACKING_ID]
		st.tp_tracking_id_max = id_info and id_info.maximum
		if not st.tp_tracking_id_max or st.tp_tracking_id_max <= 0 then
			st.tp_tracking_id_max = 65535
		end
		st.tp_next_tracking_id = math.floor(st.tp_tracking_id_max / 2)
	end

	device:connect("evdev-frame", function(dev, frame, timestamp)
		-- Both branches below used to each do their own `for _, ev in
		-- ipairs(frame)` pass -- meaning every real touch frame (fired
		-- at the touchpad's full polling rate, ~90Hz, for the entire
		-- duration of ANY touch interaction, not just ones this plugin
		-- cares about) got walked twice. Confirmed live this was
		-- costing real time: libinput itself started logging "client
		-- bug: event processing lagging behind ... your system is too
		-- slow" for this exact device, and a touchpad-gesture-driven
		-- desktop-switch animation visibly stuttered a few times while
		-- it played -- a multi-finger gesture means more events per
		-- frame (more active slots), making the double-iteration cost
		-- worse exactly when it's most likely to matter. Merged into a
		-- single pass; every event still only matches one branch in
		-- practice, since a touchpad never emits REL_WHEEL_HI_RES and
		-- a mouse never emits ABS_MT_*.
		local prev_active_count
		local prev_active_slots
		if st.tp_resolution then
			prev_active_count = st.tp_active_count
			-- Snapshot which slots were active *before* this frame's
			-- events are applied -- a two-finger lift typically sends
			-- both slots' TRACKING_ID=-1 within this same frame, which
			-- would otherwise leave no way to recover which two slots
			-- (and therefore whose last-known x/y) just lifted. Only
			-- ever consulted below when prev_active_count == 2 (see
			-- that check further down), so only allocate it then --
			-- this used to run unconditionally on every single frame,
			-- including the entire duration of e.g. a 4-finger
			-- desktop-switch swipe that this plugin never acts on,
			-- for a table this code would then just throw away
			-- unused.
			if prev_active_count == 2 then
				prev_active_slots = {}
				for slot in pairs(st.tp_active_slots) do
					prev_active_slots[slot] = true
				end
			end
		end

		for _, ev in ipairs(frame) do
			if st.tp_resolution then
				if ev.usage == evdev.ABS_MT_SLOT then
					st.tp_current_slot = ev.value
				elseif ev.usage == evdev.ABS_MT_TRACKING_ID then
					if ev.value == -1 then
						st.tp_active_slots[st.tp_current_slot] = nil
					else
						st.tp_active_slots[st.tp_current_slot] = true
					end
				elseif ev.usage == evdev.ABS_MT_POSITION_X then
					st.tp_slot_x[st.tp_current_slot] = ev.value
				elseif ev.usage == evdev.ABS_MT_POSITION_Y then
					st.tp_slot_y[st.tp_current_slot] = ev.value
				end
			end

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

		if st.tp_resolution then

			st.tp_active_count = 0
			for _ in pairs(st.tp_active_slots) do
				st.tp_active_count = st.tp_active_count + 1
			end

			if st.tp_active_count == 2 then
				local avg_y = tp_avg_active_y(st)
				if avg_y and st.tp_last_avg_y and st.tp_last_sample_ts then
					local dt = timestamp - st.tp_last_sample_ts
					if dt > 0 and dt < MAX_EVENT_GAP_US then
						local delta_mm = (avg_y - st.tp_last_avg_y) / st.tp_resolution
						st.tp_last_velocity = (delta_mm / dt) * TICK_US
					end
				end
				if avg_y then
					st.tp_last_avg_y = avg_y
					st.tp_last_sample_ts = timestamp
				end
			elseif prev_active_count == 2 and st.tp_active_count < 2 then
				-- Genuinely lifted out of a two-finger touch (count
				-- dropped to 0 or 1) -- NOT a third finger joining
				-- (count would rise to 3, e.g. moving into an unrelated
				-- swipe gesture), which must never be treated as a lift.
				local v = st.tp_last_velocity
				st.tp_last_avg_y = nil
				st.tp_last_sample_ts = nil
				st.tp_last_velocity = nil

				if v and math.abs(v) > TOUCHPAD_MIN_VELOCITY_TO_COAST_MM then
					local slot_a, slot_b = nil, nil
					for slot in pairs(prev_active_slots) do
						if slot_a == nil then
							slot_a = slot
						else
							slot_b = slot
						end
					end

					if slot_a ~= nil and slot_b ~= nil then
						st.tp_coast_slot_a = slot_a
						st.tp_coast_slot_b = slot_b
						-- The `or 0`/`or min_y` fallbacks below should be
						-- unreachable in practice -- a real touch always
						-- reports its position before it could ever
						-- become one of the two just-lifted slots -- kept
						-- only so a coast can't crash on a genuinely
						-- missing value.
						st.tp_coast_x_a = st.tp_slot_x[slot_a] or 0
						st.tp_coast_y_a = st.tp_slot_y[slot_a] or st.tp_position_min_y
						st.tp_coast_x_b = st.tp_slot_x[slot_b] or 0
						st.tp_coast_y_b = st.tp_slot_y[slot_b] or st.tp_position_min_y
						st.tp_coast_id_a = tp_next_tracking_id(st)
						st.tp_coast_id_b = tp_next_tracking_id(st)
						st.tp_coast_v = clamp(v, -TOUCHPAD_MAX_VELOCITY_MM, TOUCHPAD_MAX_VELOCITY_MM)
						st.tp_coasting = true
						st.tp_coast_first_tick = true
						libinput:timer_set_relative(TICK_US)
					end
				end
			else
				-- Covers everything else: 0 or 1 active slots (already
				-- not mid-2fg-tracking, so this is a no-op), and
				-- crucially 3+ -- entering or continuing a 3+ finger
				-- gesture must immediately invalidate any in-progress
				-- 2fg velocity tracking, not wait for it to be cleared
				-- by the lift branch above. Otherwise a 3+ finger
				-- gesture whose fingers lift asynchronously can pass
				-- back through exactly 2 active slots on its way to 0,
				-- and the lift branch would misread that as a genuine
				-- 2fg flick using stale velocity data left over from
				-- whatever the last real 2fg scroll was -- confirmed
				-- live as the actual cause of a real bug: a
				-- 3-finger desktop-switch swipe was triggering a
				-- bogus coast this way, injecting confusing extra
				-- touch frames right as KWin's own 3-finger gesture
				-- recognition was trying to run, causing bad stutter.
				st.tp_last_avg_y = nil
				st.tp_last_sample_ts = nil
				st.tp_last_velocity = nil
			end
		end

		return nil -- pass the real event through unmodified
	end)

	device:connect("device-removed", function(dev)
		devices[dev] = nil
	end)
end)
