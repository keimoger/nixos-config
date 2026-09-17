-- Compensates for perceived low resolution during slow, deliberate
-- single-finger touchpad movement.
--
-- Two confirmed facts explain the "gridded"/low-resolution feel:
--   1. This touchpad's native sensor resolution really is only 12 units/mm
--      (measured directly via `libinput measure touchpad-size` and by
--      watching raw evdev-frame deltas -- not a misconfiguration).
--   2. libinput's own touchpad filter (evdev-mt-touchpad.c /
--      filter-touchpad.c, confirmed by direct source reading) applies a
--      hardcoded `TP_MAGIC_SLOWDOWN = 0.2968` multiplier to ALL touchpads,
--      regardless of native resolution, before its normal acceleration
--      curve ever runs. 12 * 0.2968 = 3.56 -- almost exactly the "~3
--      units/mm" feel reported, which lines up neatly with the arithmetic.
--
-- Earlier attempt: injecting synthetic time-interpolated intermediate
-- positions (spreading a hop across several ms via a plugin timer). That
-- produced random ~300-500ms input hangs (root cause never isolated) and
-- barely changed the feel even when it worked, because the real problem
-- isn't timing -- it's magnitude.
--
-- This version reverse-engineered what Windows' own Synaptics driver
-- (SynTPUWP.sys) actually does for this: its config defaults show
-- `AdjustPointerMotionSpeedWithReportRate` enabled and
-- `TouchBufferPosFilter` (a position-buffer smoothing filter) DISABLED by
-- default -- i.e. stock Windows scales motion magnitude rather than
-- delaying/interpolating position delivery over time. So the base
-- mechanism here is: scale the real, already-arrived delta before it
-- reaches libinput's own acceleration curve, proportionally more for
-- small hops (to counteract TP_MAGIC_SLOWDOWN specifically in the regime
-- where it's actually noticeable) and fading to no change at all for
-- anything past a few raw units, so already-fine fast-flick behavior is
-- untouched.
--
-- One unavoidable consequence of scaling a naturally-integer 1-raw-unit
-- hop by ~3.4x: the smallest possible nonzero OUTPUT step is now ~3 raw
-- units instead of 1 -- visible as a coarser "3 pixels at a time" feel
-- even though overall sensitivity is fixed. To soften that without giving
-- up the gain, small qualifying hops are split into two sub-steps (half
-- now, half via a single one-shot timer a few ms later) instead of
-- delivered as one jump.
--
-- This reintroduces limited timer use, which is what caused random
-- ~300-500ms input hangs in an earlier, much more complex version of this
-- plugin (root cause never conclusively isolated). The most likely
-- culprit in hindsight: that version's timer handler unconditionally
-- rescheduled itself for as long as ANY interpolation was in progress
-- (`if any_interpolating() then timer_set_relative(...) end`), a
-- self-perpetuating loop that could never let go if that state ever got
-- stuck. This version has no such loop: each hop schedules at most ONE
-- one-shot fire, which is never re-armed by the timer callback itself,
-- and a hop superseded by newer real movement before its timer fires just
-- has its pending tail silently dropped (safe, because the next hop's
-- delta is always computed against the true raw hardware position, never
-- against what was actually displayed -- so nothing is lost, only the
-- exact on-screen pacing of an already-superseded hop changes).
--
-- Lives at /etc/libinput/plugins/60-touchpad-smoothing.lua.

version = libinput:register({ 1 })

-- ---- tuning -------------------------------------------------------------
local GAIN_MAX = 3.4 -- applied to a hop of ~0 raw units. Chosen as
-- 1 / TP_MAGIC_SLOWDOWN (0.2968) -- i.e. this
-- specifically cancels libinput's fixed slowdown
-- constant right at the low end, rather than being
-- an arbitrary sensitivity boost.
local GAIN_TAPER_DELTA = 6 -- raw units; gain linearly fades from GAIN_MAX
-- (at 0) down to 1.0 (no change at all) by this
-- distance. Slow careful movement was captured
-- producing mostly 0-1 unit hops, so this covers
-- that regime and a bit past it, while genuinely
-- fast movement (60-80 units/frame, confirmed via
-- capture to already feel fine) is well past the
-- taper and completely untouched.
local MID_DELAY_US = 4000 -- delay before delivering the second half of a
-- split hop -- roughly half this touchpad's own
-- confirmed ~7-8ms poll interval, so the split
-- lands between two real samples rather than
-- competing with the next one.
-- ---------------------------------------------------------------------

local devices = {}

local function state_for(device)
	local st = devices[device]
	if not st then
		st = {
			active_slots = 0, -- how many touches currently down
			current_slot = nil, -- which ABS_MT_SLOT is selected right now
			last_x = nil,
			last_y = nil, -- last REAL position we saw for this touch
			pending = nil, -- second half of a split hop still owed, or nil
		}
		devices[device] = st
	end
	return st
end

local function round(v)
	return math.floor(v + 0.5)
end

local function gain_for(dist)
	if dist >= GAIN_TAPER_DELTA then
		return 1.0
	end
	return GAIN_MAX - (GAIN_MAX - 1.0) * (dist / GAIN_TAPER_DELTA)
end

-- Delivers the second half of a split hop, if one is still owed by the
-- time this fires. A hop superseded by newer real movement in the
-- meantime already cleared `pending` itself -- see the comment at the top
-- of the file for why that's safe. Never reschedules itself.
libinput:connect("timer-expired", function(now)
	for device, st in pairs(devices) do
		if st.pending then
			device:append_frame({
				{ usage = evdev.ABS_MT_POSITION_X, value = st.pending.x },
				{ usage = evdev.ABS_MT_POSITION_Y, value = st.pending.y },
			})
			st.pending = nil
		end
	end
end)

libinput:connect("new-evdev-device", function(device)
	local st = state_for(device)

	device:connect("evdev-frame", function(dev, frame, timestamp)
		local new_x, new_y
		local touch_started = false

		for _, ev in ipairs(frame) do
			if ev.usage == evdev.ABS_MT_SLOT then
				st.current_slot = ev.value
			elseif ev.usage == evdev.ABS_MT_TRACKING_ID then
				if ev.value == -1 then
					st.active_slots = math.max(0, st.active_slots - 1)
				else
					st.active_slots = st.active_slots + 1
					touch_started = true
				end
				-- A touch starting or ending invalidates the "last real
				-- position" baseline -- don't scale a delta across it.
				st.last_x, st.last_y = nil, nil
			elseif ev.usage == evdev.ABS_MT_POSITION_X then
				new_x = ev.value
			elseif ev.usage == evdev.ABS_MT_POSITION_Y then
				new_y = ev.value
			end
		end

		if st.active_slots ~= 1 then
			return nil
		end

		-- A brand new touch: this frame (or one just like it) carries the
		-- real contact point, which IS the baseline everything after it
		-- gets diffed against -- capture it here, directly, rather than
		-- waiting for a later frame to backfill it lazily. Deferring this
		-- was the actual bug behind both symptoms reported: with no real
		-- baseline recorded at contact, a straight horizontal or vertical
		-- drag (which may never update the other axis at all) could go
		-- the entire gesture without ever completing BOTH axes' baseline
		-- -- silently skipping scaling the whole time (the "dead zone").
		-- And whenever a baseline eventually did get backfilled several
		-- frames late, the next real delta reflected several frames of
		-- accumulated travel at once, then got amplified -- the initial
		-- "jumped like crazy" overshoot.
		if touch_started or (st.last_x == nil and st.last_y == nil) then
			if new_x then
				st.last_x = new_x
			end
			if new_y then
				st.last_y = new_y
			end
			return nil -- contact point itself is never scaled, only what follows it
		end

		if not new_x and not new_y then
			return nil
		end

		-- Each axis is tracked independently from here on -- a frame that
		-- only updates one axis must not block scaling on that axis just
		-- because the other axis hasn't moved since contact.
		local old_x = st.last_x or new_x
		local old_y = st.last_y or new_y
		local cur_x = new_x or old_x
		local cur_y = new_y or old_y

		local dx = cur_x - old_x
		local dy = cur_y - old_y
		local dist = math.sqrt(dx * dx + dy * dy)

		-- Baseline for the NEXT delta is always the true, real hardware
		-- position -- never the scaled output -- so scaling never
		-- compounds or drifts away from what the sensor actually reports.
		st.last_x, st.last_y = cur_x, cur_y

		-- Any still-outstanding tail from a previous hop is superseded by
		-- this real event -- drop it rather than let it fire later and
		-- snap the cursor back to a now-stale coordinate.
		st.pending = nil

		if dist == 0 or dist >= GAIN_TAPER_DELTA then
			return nil -- nothing to do, or already past the taper: pass through unmodified
		end

		local gain = gain_for(dist)
		local out_x = round(old_x + dx * gain)
		local out_y = round(old_y + dy * gain)
		local mid_x = round(old_x + dx * gain * 0.5)
		local mid_y = round(old_y + dy * gain * 0.5)

		st.pending = { x = out_x, y = out_y }
		libinput:timer_set_relative(MID_DELAY_US)

		local rest = {}
		for _, ev in ipairs(frame) do
			if ev.usage == evdev.ABS_MT_POSITION_X then
				table.insert(rest, { usage = evdev.ABS_MT_POSITION_X, value = mid_x })
			elseif ev.usage == evdev.ABS_MT_POSITION_Y then
				table.insert(rest, { usage = evdev.ABS_MT_POSITION_Y, value = mid_y })
			else
				table.insert(rest, ev)
			end
		end
		return rest
	end)

	device:connect("device-removed", function(dev)
		devices[dev] = nil
	end)
end)
