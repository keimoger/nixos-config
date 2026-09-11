# System tray toggle for screen + touchpad auto-rotation, and (as of
# tonight's investigation) the keyboard-disable-on-rotation bug.
#
# Background: this laptop's EC disables the keyboard when physically
# rotated onto its side, even in normal laptop-open posture (not just
# full tablet-fold). Extensive earlier investigation (unbinding every
# individual IIO sensor instance one at a time -- accel_3d, dev_
# rotation, gravity, relative_orientation, geomagnetic_orientation,
# gyro_3d, magn_3d, ISH prox) had zero effect and concluded this was
# an EC-firmware-autonomous behavior, invisible to and unfixable from
# Linux.
#
# That conclusion turned out to be wrong, or at least incomplete: on
# Windows, disabling "Intel Integrated Sensor Solution" in Device
# Manager (the whole ISH controller, not an individual sensor) does
# fix it. The missing piece was that Windows' "disable" invokes an
# actual ACPI/PCI power-down, not just a driver detach -- confirmed by
# testing here: unbinding the ISH's PCI driver (intel_ish_ipc, PCI
# device 0000:00:12.0) alone left the device powered (D0, "active")
# and had no effect either, exactly matching the earlier IIO-level
# unbind results. Only after also removing the intel_ishtp_hid kernel
# module (the ISH-to-HID-bus bridge) did the device actually go
# quiet enough for the keyboard to stay enabled through rotation.
#
# The trade-off is real and unavoidable: with the sensor hub live,
# screen + touchpad rotation work but the keyboard disables on
# rotation. With it powered down, the keyboard stays enabled but
# rotation stops entirely (frozen at whatever orientation it was in).
# This toggle lets you pick per-use-case rather than committing to
# one or the other permanently.
{ pkgs, ... }:
let
  # Full teardown of the whole chain, leaves first. An earlier, lighter
  # version of this script left hid_sensor_hub and its leaf drivers
  # loaded (reasoning: they're plain HID-bus drivers that should
  # auto-rebind once the transport comes back) -- that worked once,
  # then failed on a later attempt (kscreen fell back to "incapable"
  # and iio-sensor-proxy reported "undefined" after resume), so it
  # wasn't reliable enough to leave as-is. Tearing everything down
  # explicitly and rebuilding it below is slower but has been the only
  # version that's come back clean every time tested.
  ishSuspend = pkgs.writeShellScript "ish-sensor-suspend" ''
    set -e
    if [ -e /sys/bus/pci/drivers/intel_ish_ipc/0000:00:12.0 ]; then
      echo 0000:00:12.0 > /sys/bus/pci/drivers/intel_ish_ipc/unbind
    fi
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_custom_intel_hinge || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_magn_3d || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_prox || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_gyro_3d || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_custom || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_rotation || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_accel_3d || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_incl_3d || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_trigger || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_iio_common || true
    ${pkgs.kmod}/bin/modprobe -r hid_sensor_hub || true
    ${pkgs.kmod}/bin/modprobe -r kfifo_buf || true
    ${pkgs.kmod}/bin/modprobe -r industrialio || true
    ${pkgs.kmod}/bin/modprobe -r intel_ishtp_hid || true
    ${pkgs.kmod}/bin/modprobe -r intel_ishtp_loader || true
    ${pkgs.kmod}/bin/modprobe -r intel_ish_ipc || true
    ${pkgs.kmod}/bin/modprobe -r intel_ishtp || true
  '';

  ishResume = pkgs.writeShellScript "ish-sensor-resume" ''
    set -e
    ${pkgs.kmod}/bin/modprobe intel_ishtp
    ${pkgs.kmod}/bin/modprobe intel_ish_ipc
    ${pkgs.kmod}/bin/modprobe intel_ishtp_loader || true
    ${pkgs.kmod}/bin/modprobe intel_ishtp_hid || true
    ${pkgs.kmod}/bin/modprobe industrialio || true
    ${pkgs.kmod}/bin/modprobe kfifo_buf || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_iio_common || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_trigger || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_hub || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_accel_3d || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_incl_3d || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_rotation || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_custom || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_gyro_3d || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_prox || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_magn_3d || true
    ${pkgs.kmod}/bin/modprobe hid_sensor_custom_intel_hinge || true
    sleep 1
    ${pkgs.systemd}/bin/systemctl restart iio-sensor-proxy
  '';

  pythonWithDbus = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);

  trayScript = pkgs.writeText "rotation-lock-tray.py" ''
    #!/usr/bin/env python3
    """
    System tray toggle for screen + touchpad auto-rotation (StatusNotifierItem
    protocol -- the native KDE/Wayland tray standard). Click to toggle between
    the sensor being live (rotation works, keyboard disables on physical
    rotation) and suspended (rotation frozen, keyboard stays enabled).
    """
    import asyncio
    import json
    import subprocess
    import time

    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, dbus_property, method, signal
    from dbus_next import PropertyAccess

    OUTPUT = "eDP-1"
    TOUCHPAD_SERVICE = "touchpad-autorotate.service"
    SUSPEND_SCRIPT = "${ishSuspend}"
    RESUME_SCRIPT = "${ishResume}"


    # kscreen-doctor -o's human-readable output is ANSI-colored, and a
    # naive string split (line.rsplit(":", 1)) silently captured the
    # trailing color-reset escape code along with the value -- e.g.
    # "\x1b[0;0mincapable" instead of "incapable" -- so it never
    # actually matched "never"/"incapable" in comparisons downstream.
    # That was a real, live bug tonight: every click concluded "not
    # locked" and kept re-running the lock sequence, never unlocking.
    # -j/--json avoids the whole class of problem.
    POLICY_NAMES = {0: "never", 1: "inTabletMode", 2: "always"}

    def get_current_policy() -> str:
        result = subprocess.run(
            ["${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor", "-j"],
            capture_output=True, text=True, check=True,
        )
        data = json.loads(result.stdout)
        for output in data.get("outputs", []):
            if output.get("connected"):
                # Field is entirely absent when kscreen considers the
                # output incapable of auto-rotation (no sensor) --
                # not a distinct enum value in the JSON, unlike the
                # human-readable "-o" form which prints "incapable".
                policy = output.get("autoRotatePolicy")
                if policy is None:
                    return "incapable"
                return POLICY_NAMES.get(policy, "incapable")
        return "incapable"


    def _run_logged(cmd):
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAILED ({result.returncode}): {' '.join(cmd)}", flush=True)
            if result.stdout:
                print(f"  stdout: {result.stdout.strip()}", flush=True)
            if result.stderr:
                print(f"  stderr: {result.stderr.strip()}", flush=True)
        return result


    def _notify(title, body):
        # A separate, simpler feedback mechanism from the tray icon
        # itself -- the icon's own visual refresh has proven
        # unreliable tonight (client-side caching quirk, not yet
        # root-caused), so this gives progress/completion feedback
        # that doesn't depend on it working.
        subprocess.run(
            ["${pkgs.libnotify}/bin/notify-send", "--app-name=Rotation Lock", title, body],
            check=False,
        )


    class RotationLockItem(ServiceInterface):
        def __init__(self):
            super().__init__("org.kde.StatusNotifierItem")
            self.locked = get_current_policy() == "never"
            # Guards against overlapping toggles -- the underlying
            # kernel module reload takes several seconds, and without
            # this, clicking again mid-transition would kick off a
            # second, conflicting operation instead of queuing or
            # being ignored, which is what caused the "took 3 clicks"
            # confusion during testing.
            self.busy = False

        def _apply_sync(self):
            # Every step is best-effort logged rather than raised --
            # an uncaught exception here would leave self.locked
            # already flipped but skip the icon-update code below it
            # in _toggle(), desyncing the displayed state from what
            # was actually (partially) applied with no visible error.
            # This happened for real during testing (sudo wasn't on
            # the service's PATH) and looked like "clicking does
            # nothing" from the outside.
            try:
                kscreen_doctor = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor"
                systemctl = "${pkgs.systemd}/bin/systemctl"
                if self.locked:
                    _run_logged(["/run/wrappers/bin/sudo", "-n", SUSPEND_SCRIPT])
                    _run_logged([kscreen_doctor, f"output.{OUTPUT}.autoRotatePolicy.never"])
                    _run_logged([systemctl, "--user", "stop", TOUCHPAD_SERVICE])
                else:
                    _run_logged(["/run/wrappers/bin/sudo", "-n", RESUME_SCRIPT])
                    # KWin needs its own time after iio-sensor-proxy
                    # restarts to notice the sensor is back and mark
                    # the output "capable" again -- setting the policy
                    # before that happens gets silently ignored
                    # (kscreen-doctor -o keeps reporting "incapable"),
                    # which is what caused "keyboard fixed but screen
                    # still doesn't rotate" after unlocking. Poll for
                    # readiness instead of guessing a fixed delay.
                    ready = False
                    for _ in range(20):
                        policy = get_current_policy()
                        if policy != "incapable":
                            ready = True
                            break
                        time.sleep(0.5)
                    if not ready:
                        print("WARNING: sensor still 'incapable' after 10s wait", flush=True)
                    _run_logged([kscreen_doctor, f"output.{OUTPUT}.autoRotatePolicy.always"])
                    _run_logged([systemctl, "--user", "start", TOUCHPAD_SERVICE])
            except Exception as e:
                print(f"EXCEPTION in _apply_sync: {e!r}", flush=True)

        async def _toggle(self):
            if self.busy:
                return
            self.busy = True
            try:
                # Re-derive the current state from reality rather than
                # trusting self.locked, which can drift out of sync
                # with what's actually running -- confirmed happening
                # live tonight after manual testing/reboots (a click
                # tried to suspend an already-suspended sensor and
                # instantly failed trying to unbind an already-unbound
                # driver). "incapable" counts as currently-locked here
                # too, since that's what kscreen reports whenever the
                # sensor is actually gone, regardless of which policy
                # value we last tried to set.
                currently_locked = get_current_policy() in ("never", "incapable")
                self.locked = not currently_locked
                _notify(
                    "Rotation lock",
                    "Locking (screen/touchpad rotation off, keyboard stays enabled)..."
                    if self.locked
                    else "Unlocking (rotation resuming, keyboard may disable when rotated)...",
                )
                # The actual module reload takes several seconds and
                # would otherwise block the whole D-Bus event loop
                # (freezing the tray icon and queuing up any further
                # clicks) -- offload it to a thread so Activate()
                # returns immediately.
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, self._apply_sync)
            finally:
                self.busy = False
            _notify(
                "Rotation lock",
                "Locked -- keyboard stays enabled, rotation frozen."
                if self.locked
                else "Unlocked -- rotation active, keyboard may disable when rotated.",
            )
            # Isolated from _apply_sync's own try/except -- if the tray
            # host's icon caching behaves differently than expected,
            # a failure here should still surface in the log rather
            # than silently vanish, and it shouldn't be able to make
            # the underlying toggle (which already succeeded above)
            # look like it failed too.
            try:
                self.NewIcon()
                self.NewToolTip()
                self.NewStatus("locked" if self.locked else "unlocked")
                self.emit_properties_changed(
                    {
                        "IconName": self.IconName,
                        "Status": self.Status,
                    }
                )
            except Exception as e:
                print(f"EXCEPTION emitting icon/status update: {e!r}", flush=True)

        @method()
        def Activate(self, x: "i", y: "i"):
            asyncio.get_running_loop().create_task(self._toggle())

        @method()
        def SecondaryActivate(self, x: "i", y: "i"):
            asyncio.get_running_loop().create_task(self._toggle())

        @method()
        def Scroll(self, delta: "i", orientation: "s"):
            pass

        @method()
        def ContextMenu(self, x: "i", y: "i"):
            pass

        @dbus_property(access=PropertyAccess.READ)
        def Category(self) -> "s":
            return "Hardware"

        @dbus_property(access=PropertyAccess.READ)
        def Id(self) -> "s":
            return "rotation-lock"

        @dbus_property(access=PropertyAccess.READ)
        def Title(self) -> "s":
            return "Rotation Lock"

        @dbus_property(access=PropertyAccess.READ)
        def Status(self) -> "s":
            return "Active"

        @dbus_property(access=PropertyAccess.READ)
        def IconName(self) -> "s":
            return "rotation-locked" if self.locked else "rotation-allowed"

        @dbus_property(access=PropertyAccess.READ)
        def ItemIsMenu(self) -> "b":
            return False

        @dbus_property(access=PropertyAccess.READ)
        def ToolTip(self) -> "(sa(iiay)ss)":
            state = "Rotation locked (keyboard stays enabled)" if self.locked else "Rotation unlocked"
            desc = (
                "Screen and touchpad are frozen; the orientation sensor is fully "
                "powered down so the keyboard won't disable when rotated. Click to unlock."
                if self.locked
                else "Screen and touchpad follow the sensor. Rotating onto its side will "
                "disable the keyboard (firmware behavior). Click to lock."
            )
            return [self.IconName, [], state, desc]

        @signal()
        def NewIcon(self):
            pass

        @signal()
        def NewToolTip(self):
            pass

        @signal()
        def NewStatus(self, status: "s"):
            pass


    async def main():
        bus = await MessageBus().connect()
        item = RotationLockItem()
        bus.export("/StatusNotifierItem", item)

        service_name = f"org.kde.StatusNotifierItem-{__import__('os').getpid()}-1"
        await bus.request_name(service_name)

        watcher = bus.get_proxy_object(
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            await bus.introspect("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"),
        )
        watcher_iface = watcher.get_interface("org.kde.StatusNotifierWatcher")
        await watcher_iface.call_register_status_notifier_item(service_name)

        await asyncio.Event().wait()


    if __name__ == "__main__":
        asyncio.run(main())
  '';
in
{
  # Scoped precisely to these two exact, content-addressed script
  # paths -- not a broad NOPASSWD grant. Nix store immutability means
  # this rule can't be tricked into running anything else by editing
  # the target file; a content change produces a different store path
  # and this rule would need to be rebuilt to match it.
  security.sudo.extraRules = [
    {
      users = [ "keimoger" ];
      commands = [
        {
          command = "${ishSuspend}";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${ishResume}";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.user.services.rotation-lock-tray = {
    description = "System tray toggle for screen/touchpad auto-rotation and keyboard-on-rotation trade-off";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pythonWithDbus}/bin/python3 ${trayScript}";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
