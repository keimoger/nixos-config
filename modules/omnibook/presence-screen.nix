# Windows-style "presence sensing": turn the screen off when nobody's
# in front of the laptop, back on the moment someone is again.
#
# This laptop has an ISH-attached HID proximity sensor (confirmed via
# `udevadm info`: HID-SENSOR-200011.*.auto, HID Sensor usage page
# 0x20/0x11 "Proximity" -- the same physical signal Windows' own
# presence/adaptive-dimming feature reads), turned on by
# `hardware.sensor.iio.enable` in sensors.nix for tablet-mode posture.
#
# Originally built on top of iio-sensor-proxy's `net.hadess.SensorProxy`
# D-Bus service (the "proper" desktop-standard way to consume this) --
# abandoned after live testing (captured with iio-sensor-proxy running
# standalone in --verbose mode, G_MESSAGES_DEBUG=all, while physically
# moving toward/away from the sensor) showed its "IIO Poll proximity
# sensor" driver reads this device's proximity channel exactly ONCE, at
# the moment a client calls ClaimProximity(), and never polls it again
# for the rest of the session -- ProximityNear just permanently freezes
# at whatever it read at claim time. Confirmed via two separate debug
# captures; not a threshold or udev-config issue (PROXIMITY_NEAR_LEVEL
# was being read and applied correctly).
#
# This instead polls the same sensor's raw sysfs value directly, once a
# second, bypassing iio-sensor-proxy's proximity subsystem entirely.
# Also empirically calibrated live (polling raw sysfs values in a tight
# loop while physically stepping back ~1-2m from the laptop and
# returning): `in_proximity1_raw` turned out to be far too noisy to
# threshold reliably (fluctuates ~300-700 even while sitting still at
# normal desk distance) and `in_proximity0_raw` barely moves at all.
# `in_attention_input`, by contrast, is a clean boolean the whole time:
# pinned at 100 while present, drops to exactly 0 only while genuinely
# away, with no fuzzy middle ground observed in testing -- this is the
# dedicated HID "human presence / attention" field (distinct from the
# raw distance-style proximity channels), so no threshold tuning is
# needed at all: just check for nonzero.
#
# Two separate `iio:deviceN` paths were found exposing this identically
# (one reached via this laptop's USB camera module, one via the ISH --
# see the udevadm path difference in each device's `device -> ...`
# symlink target if you go looking) -- both tracked in lockstep in every
# capture taken, so this treats them as redundant copies of the same
# signal: present if ANY readable one reports nonzero, away only once
# ALL readable ones agree on zero. Device numbering under
# /sys/bus/iio/devices isn't guaranteed stable across reboots, so paths
# are re-discovered by matching on `name == "prox"` rather than
# hardcoding "iio:device5"/"iio:device6".
#
# This only drives DPMS (screen power), not the lock screen -- matching
# what was actually asked for. Plasma's own idle-timeout DPMS keeps
# working independently alongside this; they can't fight each other
# since this daemon only ever calls `--dpms on` in response to its own
# earlier `--dpms off` (tracked in `screen_off` below), never
# unconditionally.
{ pkgs, ... }:
let
  daemonScript = pkgs.writeText "presence-screen-daemon.py" ''
    #!/usr/bin/env python3
    """
    Polls this laptop's HID proximity sensor's "attention" field directly
    via sysfs and toggles the screen's DPMS state to match -- on while
    someone's in front of the laptop, off a debounce period after they
    leave. See the header comment in presence-screen.nix for why this
    bypasses iio-sensor-proxy's own (broken, for this sensor) D-Bus
    proximity handling instead of using it.
    """
    import glob
    import subprocess
    import time

    KSCREEN_DOCTOR = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor"

    # was 0.1 -- a constant 10Hz background wakeup, all day, was the
    # leading suspect for why Power Saver mode started visibly hurting
    # KWin animation smoothness after this daemon was added (switching
    # to the Performance power profile made the stutter disappear,
    # consistent with a steady trickle of small wakeups interfering
    # with how fast the CPU ramps up for a latency-sensitive animation
    # frame under Power Saver's more conservative frequency scaling --
    # not proven with real profiling, but the best-supported theory,
    # and this was the one genuinely new constant background wakeup
    # source this daemon introduced). 0.3s still wakes the screen well
    # under a second after you look back, just with a third of the
    # constant background noise.
    POLL_INTERVAL_SECONDS = 0.3

    # How long "away" must persist before the screen actually turns off.
    # A single instant "far" reading is common (a hand briefly passing
    # over the sensor) and would otherwise blank the screen on every such
    # moment. Deliberately no equivalent delay for turning back on --
    # presence returning should feel instant, the same way Windows' own
    # version of this wakes immediately.
    AWAY_DEBOUNCE_SECONDS = 3


    def find_attention_paths():
        paths = []
        for name_path in glob.glob("/sys/bus/iio/devices/iio:device*/name"):
            try:
                with open(name_path) as f:
                    name = f.read().strip()
            except OSError:
                continue
            if name != "prox":
                continue
            att_path = name_path[: -len("name")] + "in_attention_input"
            paths.append(att_path)
        return paths


    def read_present(paths):
        """True/False if at least one path was readable, None if every
        path failed (device renumbered, sensor hub asleep, etc.) -- a
        None reading is deliberately never acted on, so a transient
        read failure can't be misread as "away" and blank the screen."""
        saw_reading = False
        for p in paths:
            try:
                with open(p) as f:
                    value = int(f.read().strip())
            except (OSError, ValueError):
                continue
            saw_reading = True
            if value > 0:
                return True
        return False if saw_reading else None


    def set_dpms(on: bool):
        subprocess.run(
            [KSCREEN_DOCTOR, "--dpms", "on" if on else "off"],
            check=False,
        )


    def log(msg):
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


    def main():
        # Device numbers under /sys/bus/iio/devices are not stable --
        # confirmed live tonight, they shifted on every single suspend/
        # resume tested (e.g. iio:device5/6 -> iio:device0/2, later ->
        # iio:device6/7). find_attention_paths() was previously only
        # called once here at startup, so a renumbering left this
        # daemon permanently polling files that no longer existed --
        # silently, since a missing-file read failure was deliberately
        # non-fatal (see read_present's docstring), meaning it just
        # went blind with no further log output at all rather than
        # crashing where Restart=on-failure would have caught it. Now
        # re-discovered any time every currently-known path fails to
        # read, which covers both a renumbering and simply not having
        # found the sensor yet at startup (e.g. a race with boot).
        paths = find_attention_paths()
        log(f"watching: {paths}" if paths else "no HID proximity ('prox') sensor found yet, will keep looking")

        screen_off = False
        away_since = None
        last_present = None

        while True:
            present = read_present(paths) if paths else None
            if present is None:
                rediscovered = find_attention_paths()
                if rediscovered != paths:
                    paths = rediscovered
                    log(f"re-discovered sensor paths: {paths}")
                time.sleep(POLL_INTERVAL_SECONDS)
                continue

            if present != last_present:
                log(f"present -> {present}")
                last_present = present

            if present:
                away_since = None
                if screen_off:
                    log("presence returned -- dpms on")
                    set_dpms(True)
                    screen_off = False
            else:
                if away_since is None:
                    away_since = time.monotonic()
                    log(f"away, starting {AWAY_DEBOUNCE_SECONDS}s debounce")
                elif not screen_off and time.monotonic() - away_since >= AWAY_DEBOUNCE_SECONDS:
                    log("debounce elapsed -- dpms off")
                    set_dpms(False)
                    screen_off = True

            time.sleep(POLL_INTERVAL_SECONDS)


    if __name__ == "__main__":
        main()
  '';
in
{
  systemd.user.services.presence-screen = {
    description = "Turn the screen off/on based on the laptop's proximity sensor";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${daemonScript}";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
