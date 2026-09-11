# Accelerometer / hinge-angle sensor stack for automatic tablet mode.
#
# On this laptop, "tablet mode" is not a physical switch: it is derived
# from the Intel ISH (Integrated Sensor Hub), which exposes an
# accelerometer + inclinometer + hinge-angle sensor over HID, which
# iio-sensor-proxy turns into posture info, which KDE Plasma then uses
# to flip the UI into tablet mode. Every link in that chain has to work:
#
#   Intel ISH firmware -> intel_ish_ipc/hid_sensor_hub kernel modules ->
#   IIO devices in /sys/bus/iio -> iio-sensor-proxy -> qtsensors -> Plasma
#
# See the README in this repo for how to verify each link with dmesg /
# monitor-sensor.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.initrd.kernelModules = [
    "intel_ish_ipc"
    "intel_ishtp_hid"
    "hid_sensor_hub"
  ];

  boot.kernelModules = [
    "intel_ish_ipc"
    "intel_ishtp_hid"
    "intel_ishtp_loader"
    "hid_sensor_hub"
    "hid_sensor_accel_3d"
    "hid_sensor_incl_3d"
    "hid_sensor_rotation"
    "hp_wmi"
  ];

  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  # --- The actual blocker: model-specific ISH firmware -------------------
  #
  # Confirmed via `dmesg | grep -i ish`:
  #
  #   ISH loader: load firmware: intel/ish/ish_lnlm.bin
  #   ISH loader: cmd 2 failed 10          (repeats 3x)
  #
  # The generic Lunar Lake blob linux-firmware ships as
  # intel/ish/ish_lnlm.bin *loads* fine but is rejected by this board's
  # ISH controller ("cmd 2 failed" = firmware image mismatch, not a
  # missing-file error). This kernel isn't doing DMI-hash-based vendor
  # firmware selection — it always asks for that exact plain filename —
  # so the fix is to make our own copy of that exact path win over
  # linux-firmware's, rather than add a new hashed filename.
  #
  # The correct bytes for this exact model
  # (HP OmniBook Ultra Flip Laptop 14-fh0xxx) are written but NOT YET
  # MERGED upstream:
  #   https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/746
  # Track that MR; once it lands in a linux-firmware release, this whole
  # block becomes unnecessary and can be deleted.
  #
  # Until then:
  #   1. Get the actual firmware bytes. Two options:
  #      a) Pull the .bin out of the still-open MR above (download the
  #         patch/diff from the branch and extract the binary blob), or
  #      b) Extract it from HP's Windows Intel ISH driver package
  #         (SoftPaq) for this model on support.hp.com: download the
  #         driver .exe, extract it (e.g. `7z x sp######.exe` on Linux),
  #         and look for a similarly-named .bin under the driver payload.
  #
  #   2. Save it as ./firmware/ish_lnlm.bin next to this module (same
  #      filename as the stock one — that's what makes it "override"
  #      rather than "add").
  #
  #   3. Uncomment the block below and rebuild. hardware.firmware is a
  #      *list of directories*, searched in order, first match wins —
  #      mkBefore puts ours ahead of linux-firmware's regardless of
  #      module ordering elsewhere in the config.
  #
  #   4. Verify with `sudo dmesg | grep -i ish` again after reboot: you
  #      should see "firmware loaded" with no "cmd 2 failed" after it.
  #
  hardware.firmware = lib.mkBefore [
    (pkgs.runCommand "ish-lnlm-hp-omnibook-firmware" { } ''
      mkdir -p $out/lib/firmware/intel/ish
      install -Dm444 ${./firmware/ish_lnlm.bin} \
        $out/lib/firmware/intel/ish/ish_lnlm.bin
    '')
  ];

  # Keep iio-sensor-proxy running even if it encounters uncalibrated
  # devices at boot (it can crash-loop before the ISH firmware is fully
  # up).
  systemd.services.iio-sensor-proxy.serviceConfig = {
    Restart = "always";
    RestartSec = "5s";
  };

  hardware.sensor.iio.enable = true;

  # KDE Plasma 6 needs qtsensors explicitly to react to hinge/orientation
  # events for auto-rotate and "automatically enable touch mode" in
  # System Settings > Touchpad / Convertible. Without it, iio-sensor-proxy
  # can be working perfectly and Plasma still won't flip into tablet mode.
  environment.systemPackages = [ pkgs.kdePackages.qtsensors ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="iio", ATTR{name}=="*", ENV{PROXIMITY_NEAR_LEVEL}="100"
  '';
}
