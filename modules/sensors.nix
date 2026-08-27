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
{ config, lib, pkgs, ... }:
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
  # As shipped, linux-firmware only has a *generic* Lunar Lake ISH blob
  # (intel/ish/ish_lnlm.bin). This laptop's ISH controller needs a
  # vendor-specific variant, selected by the kernel via a filename built
  # from CRC32 hashes of your DMI strings. Without it, intel_ish_ipc only
  # brings up the proximity sensor (which is why the proximity udev rule
  # below already works) and never brings up the accelerometer/hinge
  # sensors that tablet-mode detection needs.
  #
  # The fix for this exact model is written but NOT YET MERGED upstream:
  #   https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/746
  # Track that MR; once it lands in a linux-firmware release, this whole
  # block becomes unnecessary and can be deleted.
  #
  # Until then:
  #   1. Find the exact filename the kernel is asking for:
  #        sudo dmesg | grep -i ish
  #      or, once you're on a kernel with vendor-firmware support:
  #        sudo dmidecode -s system-manufacturer
  #        sudo dmidecode -s system-product-name
  #      then compute: ish_lnlm_<crc32(manufacturer)>_<crc32(product-name)>.bin
  #      (8 hex digits each, zero-padded). For this exact model, that
  #      currently works out to:
  #        intel/ish/ish_lnlm_00b9115e_cf5da58b.bin
  #      but always double check against your own dmesg output.
  #
  #   2. Get the actual firmware bytes. Two options:
  #      a) Pull the .bin out of the still-open MR above (download the
  #         patch/diff from the branch and extract the binary blob), or
  #      b) Extract it from HP's Windows Intel ISH driver package
  #         (SoftPaq) for this model on support.hp.com: download the
  #         driver .exe, extract it (e.g. `7z x sp######.exe` on Linux),
  #         and look for a similarly-named .bin under the driver payload.
  #
  #   3. Drop the resulting file at ./firmware/ish_lnlm_<...>.bin next to
  #      this module, fix the filename below to match, and uncomment
  #      the block.
  #
  # hardware.firmware = [
  #   (pkgs.runCommand "ish-lnlm-hp-omnibook-firmware" { } ''
  #     mkdir -p $out/lib/firmware/intel/ish
  #     install -Dm444 ${./firmware/ish_lnlm_00b9115e_cf5da58b.bin} \
  #       $out/lib/firmware/intel/ish/ish_lnlm_00b9115e_cf5da58b.bin
  #   '')
  # ];

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
