# keimoger's NixOS config

## Layout

```
flake.nix                   inputs (nixpkgs, plover-flake, lanzaboote) + system def
configuration.nix           thin entry point, just imports + stateVersion
hardware-configuration.nix  machine-generated (filesystems, swap, cpu, kernel pkg)
modules/
  boot.nix                  systemd-boot + lanzaboote (secure boot)
  networking.nix            hostname, NetworkManager
  locale.nix                timezone, i18n, console font
  desktop.nix                Plasma 6 + SDDM + xkb + graphics
  audio.nix                  pipewire
  bluetooth.nix               bluetooth + bluedevil
  security.nix                fprintd fingerprint auth
  sensors.nix                 accelerometer/hinge stack -> tablet mode (see below)
  fonts.nix                    fonts + icon themes
  users.nix                    user account + uinput (needed by Plover)
  plover.nix                   stenography setup, from the plover-flake input
  packages.nix                 misc CLI tools + printing
```

Install/apply exactly as before, nothing about the flake output changed:

```
sudo nixos-rebuild switch --flake .#nixos
```

### Why split it up?

The original `configuration.nix` mixed boot, desktop, hardware, and
per-user packages in one 277-line file, and — more importantly —
`hardware-configuration.nix` had hand-written sensor/firmware settings
mixed into a file whose header literally says "Do not modify, this is
regenerated." If you ever re-run `nixos-generate-config` (new hardware,
reinstall, etc.), everything under `modules/sensors.nix` would have
silently been wiped. It now lives in its own file that `nixos-generate-config`
never touches.

Everything else is a straight lift of your existing config, split along
"what it configures" lines. No options were added or removed except the
tablet-mode fix below.

## Fixing automatic tablet mode

Your `hardware-configuration.nix` already had good instincts baked in
(`hardware.sensor.iio.enable`, the extra `hid_sensor_*` kernel modules,
the proximity udev rule) — that's not wrong, it's just incomplete. Here's
the full chain and where it currently breaks:

```
Intel ISH firmware  →  intel_ish_ipc / hid_sensor_hub kernel modules  →
IIO devices in /sys/bus/iio  →  iio-sensor-proxy  →  qtsensors  →  Plasma
```

### 1. The missing link: model-specific ISH firmware

This laptop's sensor hub (Lunar Lake ISH) needs a **vendor-specific**
firmware blob, not the generic one linux-firmware ships. Without it,
`intel_ish_ipc` only manages to bring up the proximity sensor (which is
why your proximity udev rule already "works") — the accelerometer,
inclinometer and hinge-angle sensors never come up, so there's no
posture data for anything downstream to use.

Confirmed via `sudo dmesg | grep -i ish`:

```
intel_ish_ipc 0000:00:12.0: ISH loader: load firmware: intel/ish/ish_lnlm.bin
intel_ish_ipc 0000:00:12.0: ISH loader: cmd 2 failed 10   (x3)
```

The generic blob *loads* (no file-not-found error) but gets rejected by
the sensor hub — wrong firmware image for this board, not a missing
file. The kernel here always asks for the plain `intel/ish/ish_lnlm.bin`
path, so the fix is to make our own copy of that exact filename win over
linux-firmware's copy — not add a differently-named file.

The correct bytes for this exact model
(`HP OmniBook Ultra Flip Laptop 14-fh0xxx`) have been submitted upstream
but are **still a draft, not merged**, as of this writing:
<https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/746>

`modules/sensors.nix` has a ready-to-uncomment `hardware.firmware` block
for this. To finish it:

1. Get the actual bytes, either by pulling the `.bin` out of the linked
   MR's branch, or by extracting it from HP's Windows "Intel Dynamic
   Tuning / ISH" driver SoftPaq for this model from support.hp.com
   (download the `.exe`, extract with `7z x sp######.exe` on Linux, look
   for a same-named `.bin`).
2. Save it as `modules/firmware/ish_lnlm.bin` (same filename as the
   stock one — that's what makes it override rather than add).
3. Uncomment the `hardware.firmware` block in `modules/sensors.nix` and
   rebuild.
4. Check `sudo dmesg | grep -i ish` again — you want "firmware loaded"
   with no `cmd 2 failed` after it.
5. Once the upstream MR merges and a nixpkgs update picks it up, delete
   the whole block — it becomes redundant.

### 2. Plasma also needs `qtsensors` explicitly

Separately from the firmware, KDE Plasma 6 requires `qtsensors` to be
installed for it to react to hinge/orientation events at all — it's not
pulled in automatically the way it is on some other distros. This is
already added in `modules/sensors.nix`
(`environment.systemPackages = [ pkgs.kdePackages.qtsensors ];`).

### 3. Verifying each link after rebuilding

```bash
# 1. Did the firmware load?
sudo dmesg | grep -i ish
# look for "ISH loader: firmware loaded" with no "cmd 2 failed" errors after it

# 2. Are the IIO devices there?
ls /sys/bus/iio/devices/
# expect more than just the proximity device — an accel/incl device too

# 3. Is iio-sensor-proxy seeing them?
monitor-sensor
# should print "Has accelerometer" and tilt/orientation changes as you move the laptop

# 4. Is Plasma reacting?
# System Settings > Touchpad (or Convertible/Tablet Mode Settings) >
# "Automatically enable touch mode" — flip the hinge and watch it toggle.
```

If step 1 or 2 fails, the firmware isn't loaded yet — go back to the
section above. If step 3 works but step 4 doesn't, check that
`kdePackages.qtsensors` actually landed (`nix-store -q --references` on
your system closure, or just check `which` after logging back in) and
that you restarted your Plasma session after rebuilding.
