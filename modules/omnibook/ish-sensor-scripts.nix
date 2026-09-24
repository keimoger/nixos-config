# Shared low-level recovery scripts for this laptop's Intel ISH
# (Integrated Sensor Hub) -- a full unbind + module-by-module reload of
# the whole chain from the PCI device down through every individual
# hid_sensor_* leaf driver. Used by two independent, unrelated
# consumers:
#
#   - rotation-lock.nix's tray toggle: a *manual* suspend/resume of just
#     the sensor hub, trading rotation for a working keyboard (see that
#     file's own header comment for the full story).
#   - ish-resume-hook.nix: runs this pair *automatically* after every
#     real system resume, to work around a real ISH firmware bug (see
#     that file's header comment).
#
# Not a NixOS module itself -- just a plain function returning the two
# script derivations, so both consumers get the exact same
# content-addressed store paths (letting one shared `security.sudo.
# extraRules` entry, in ish-resume-hook.nix, cover both).
{ pkgs }:
{
  # Full teardown of the whole chain, leaves first. An earlier, lighter
  # version of this left hid_sensor_hub and its leaf drivers loaded
  # (reasoning: they're plain HID-bus drivers that should auto-rebind
  # once the transport comes back) -- that worked once, then failed on
  # a later attempt (kscreen fell back to "incapable" and
  # iio-sensor-proxy reported "undefined" after resume), so it wasn't
  # reliable enough to leave as-is. Tearing everything down explicitly
  # and rebuilding it below is slower but has been the only version
  # that's come back clean every time tested.
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
}
