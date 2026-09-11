# Remaps this laptop's dedicated Copilot key to Left Ctrl.
#
# It's not a single keycode -- confirmed live via evtest on the main
# keyboard device ("AT Translated Set 2 keyboard"): pressing it sends
# a hardware-level chord, LEFTMETA + LEFTSHIFT + F23, all together.
# This is the common OEM trick for giving Windows something to bind
# "launch Copilot" to without a dedicated Linux keycode; it has no
# single-key identity of its own to remap directly.
#
# A first attempt at this used keyd with `ids = [ "*" ]` (copied
# straight from its own example config) and caused a severe live
# failure serious enough to require a hard reset: the wildcard
# doesn't scope to "whatever sends the Copilot key" -- it grabs every
# input device on the system, which on this machine includes a steno
# keyboard (see modules/plover.nix) that sends its own rapid,
# unrelated multi-key chords for Plover to interpret. keyd's own
# chord-processing engine intercepted and mangled those into garbage
# keystrokes. The fix isn't a better keyd config -- it's not using a
# device-wildcard tool at all here.
#
# This is a small, purpose-built relay instead: it opens *only* the
# exact device at this stable udev by-path symlink (tied to the
# physical i8042/PS2 keyboard controller, distinct from every USB
# device including the steno keyboard), grabs it exclusively, and
# passes every event through a virtual uinput keyboard completely
# unchanged -- except for the one specific 3-key chord, which becomes
# a clean Left Ctrl press/release instead.
#
# A second problem surfaced after this had been live for a while: the
# emitted Left Ctrl got stuck held down, requiring another reboot to
# clear. Root cause: the original version only released Left Ctrl
# once it saw clean "up" events for all three chord keys -- but these
# aren't real physical keys with guaranteed clean release behavior,
# they're a synthetic firmware chord, and if even one of the three
# release events never arrives (observed, not just theoretical), the
# internal "held" state for that key stays true forever and Left
# Ctrl never gets released. There's no way to guarantee that can't
# happen, so instead of relying on it: a watchdog force-releases Left
# Ctrl if it's been held more than CHORD_TIMEOUT seconds regardless of
# what release events did or didn't show up, bounding the worst case
# to a couple of seconds of stuck Ctrl instead of stuck-until-reboot.
# The `finally` block also now unconditionally releases it on any exit
# path (including a crash mid-chord), rather than only via the normal
# release-detection branch.
#
# A THIRD problem, found immediately after fixing the second: none of
# the above actually saved us from `systemctl stop`. Python's default
# handling of SIGTERM is immediate process termination via the OS's
# default disposition -- it does NOT raise a catchable exception the
# way Ctrl+C/SIGINT does, so it never unwinds through try/finally at
# all. The `finally` block above (and its unconditional release) never
# ran on a plain stop; confirmed live, stopping the service while a
# chord happened to be active left Left Ctrl stuck down, with the
# process and its virtual device already gone -- recovered with a one-off
# script sending a single synthetic release, not a reboot, but only
# because there happened to be a way to do that from a working
# terminal. A signal handler that turns SIGTERM into a normal,
# catchable exception is the actual fix -- now it unwinds through the
# same `finally` block like any other exit path.
{ pkgs, ... }:
let
  pythonWithEvdev = pkgs.python3.withPackages (ps: [ ps.evdev ]);

  relayScript = pkgs.writeText "copilot-key-relay.py" ''
    import select
    import signal
    import sys
    import time
    import evdev
    from evdev import ecodes, UInput

    def _handle_sigterm(signum, frame):
        print("SIGTERM received, shutting down", flush=True)
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_sigterm)

    SOURCE_PATH = "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
    CHORD_KEYS = {ecodes.KEY_LEFTMETA, ecodes.KEY_LEFTSHIFT, ecodes.KEY_F23}
    CHORD_TIMEOUT = 2.0  # seconds -- see the module comment for why this exists

    # Wait for udev to have created the symlink -- this can start
    # before the keyboard is fully enumerated, especially right at
    # boot.
    while True:
        try:
            dev = evdev.InputDevice(SOURCE_PATH)
            break
        except FileNotFoundError:
            time.sleep(1)

    dev.grab()
    print(f"Grabbed {SOURCE_PATH} (pid {__import__('os').getpid()}), relay active.", flush=True)

    cap = dev.capabilities()
    cap.pop(ecodes.EV_SYN, None)
    ui = UInput(cap, name="copilot-key-relay-keyboard")

    held = {k: False for k in CHORD_KEYS}
    chord_active = False
    chord_started_at = None

    def release_chord(reason):
        global chord_active, chord_started_at
        chord_active = False
        chord_started_at = None
        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, 0)
        ui.syn()
        for k in CHORD_KEYS:
            held[k] = False
        print(f"Left Ctrl released ({reason})", flush=True)

    try:
        while True:
            timeout = None
            if chord_active:
                elapsed = time.monotonic() - chord_started_at
                timeout = max(0.0, CHORD_TIMEOUT - elapsed)

            r, _, _ = select.select([dev.fd], [], [], timeout)

            if not r:
                # Timed out while a chord was active and still no
                # release seen for one of the three keys -- force it
                # rather than staying stuck.
                release_chord("watchdog timeout")
                continue

            for event in dev.read():
                if event.type == ecodes.EV_SYN:
                    ui.syn()
                    continue

                if event.type == ecodes.EV_KEY and event.code in CHORD_KEYS:
                    held[event.code] = event.value != 0

                    if not chord_active and all(held.values()):
                        chord_active = True
                        chord_started_at = time.monotonic()
                        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, 1)
                        print("Left Ctrl pressed (chord detected)", flush=True)
                        continue

                    if chord_active:
                        if not any(held.values()):
                            release_chord("all chord keys released")
                        continue

                    # Individual meta/shift/f23 press outside of a
                    # full chord (e.g. just tapping shift on its own)
                    # -- pass through normally, unmodified.
                    ui.write(event.type, event.code, event.value)
                    continue

                # Everything else -- pass through completely unchanged.
                ui.write(event.type, event.code, event.value)
    finally:
        if chord_active:
            ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTCTRL, 0)
            ui.syn()
            print("Left Ctrl released (process exiting mid-chord)", flush=True)
        ui.close()
        dev.ungrab()
        print("Exited cleanly.", flush=True)
  '';
in
{
  # systemd.services.copilot-key-remap = {
  #   description = "Remap this laptop's Copilot key (Meta+Shift+F23 hardware chord) to Left Ctrl";
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     ExecStart = "${pythonWithEvdev}/bin/python3 ${relayScript}";
  #     Restart = "no";
  #     RestartSec = 2;
  #   };
  # };
}
