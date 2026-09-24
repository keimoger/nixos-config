# keimoger's NixOS configuration

Declarative configuration for `keibook`, an HP OmniBook Ultra Flip
14-fh0013dx, using nixos-unstable, Plasma 6 on Wayland, Home Manager,
and plasma-manager. Dependency revisions are recorded in `flake.lock`.

## Layout

- `flake.nix`: inputs and the `nixosConfigurations.keibook` output.
- `configuration.nix`: module imports, filesystem scrubbing, and state version.
- `hardware-configuration.nix`: filesystem UUIDs and generated hardware settings.
- `modules/boot.nix`: Lanzaboote Secure Boot, build resources, zram, and hibernation.
- `modules/desktop.nix` and `modules/home-manager.nix`: desktop and user settings.
- `modules/users.nix`: account, applications, and input-device permissions.
- `modules/plover.nix`: Plover and custom plugins.
- `modules/remote-builder.nix`: distributed builds over SSH.
- `modules/omnibook/`: firmware, sensors, touchpad, graphics, biometrics,
  presence sensing, and tablet UI patches for this laptop.
- `build-nix.nu`: local, remote, and selected-package build workflows.

Removing the OmniBook import removes its customizations, but deploying to
another machine also requires replacing hardware settings, host/user paths,
and any other machine-specific settings.

## Build and activate

From this directory:

```sh
# Build without activating.
nixos-rebuild build --flake .#keibook

# Build and activate, including the boot default.
sudo nixos-rebuild switch --flake .#keibook

# Force a local build when the configured builder is unavailable.
sudo nixos-rebuild switch --flake .#keibook --builders ''
```

The Nushell helper also activates the system:

```sh
nu build-nix.nu local
nu build-nix.nu remote
nu build-nix.nu heavy
```

`local` explicitly disables distributed builders. `remote` builds the whole
system on the builder and copies it back before activation. `heavy` offloads
selected patched packages, then builds the remaining system locally.
Run the helper from this directory. Ordinary rebuild commands still use the
distributed builder configured in `modules/remote-builder.nix`.

The helper and module currently use `builder@192.168.8.16`, port 2222.
The module uses `/home/keimoger/.ssh/nix-remote-builder`; the helper uses your
SSH client configuration/agent. The LAN address needs a reachable LAN route;
Tailscale alone does not provide that route without subnet routing.

## Reproducibility and recovery

Two Plover inputs intentionally follow local edits in these directories:

- `/home/keimoger/projects/plover-russian-firebird`
- `/home/keimoger/projects/plover-altcase`

Keep these as local inputs while developing the plugins; do not replace them
with pinned upstream versions. Preserve these sources along with this repository
when recovering the machine, including unpublished edits.
Secure Boot keys in `/var/lib/sbctl`, SSH keys, application data, and other
mutable state are also outside this repository.

The root, home, and nix subvolumes share one Btrfs filesystem. A monthly scrub
is configured for `/`, avoiding duplicate scans of the same filesystem.
Scrubbing checks integrity; it is not a backup or a snapshot policy.
Off-device backups and automatic snapshots are intentionally deferred for now.

Lanzaboote retains three boot-menu generations. To recover from a bad system
update, select an older generation at boot, or use:

```sh
sudo nixos-rebuild switch --rollback
```

System rollback does not restore user files or application data. Recovery from
disk loss requires a separate backup of those files and the external state above.

## OmniBook sensor stack

The model-specific ISH firmware is already included at
`modules/omnibook/firmware/ish_lnlm.bin` and installed by
`modules/omnibook/sensors.nix`. That module also enables the kernel sensor
modules, iio-sensor-proxy, and Qt sensors. The resume hook resets the ISH stack
after wake; rotation-lock uses the same shared recovery scripts.

Useful checks after rebuilding and rebooting:

```sh
sudo dmesg | grep -i ish
ls /sys/bus/iio/devices/
systemctl status iio-sensor-proxy
monitor-sensor
```

Check firmware loading first, then IIO device creation, sensor reports, and
finally Plasma's response to orientation changes. Custom libinput and Plasma
patches live under `modules/omnibook/patches/`; input updates can require
adjusting these patches and rebuilding their dependent packages.
