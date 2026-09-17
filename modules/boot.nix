{ ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Build parallelism, tuned for this laptop's 8 logical cores / 15GB RAM.
  # Was max-jobs=1 (previously lived in modules/omnibook/touchpad.nix,
  # added alongside the libinput patch overlay there -- but this is a
  # global nix-daemon setting, not something touchpad-specific, so it
  # didn't belong in that file once it needed real tuning instead of
  # just "be maximally conservative").
  #
  # Was max-jobs=2 / cores=4 -- split this way so two mid-size
  # derivations could build concurrently instead of one giant compile
  # (e.g. a single heavy Qt/KDE package) claiming every core and a
  # correspondingly large slice of RAM at once, back when there were
  # dozens of small derivations queued at once (the plasma-*.drv pile
  # from the cursor-accel rebuild). In practice most rebuilds since
  # then have been a single big package (kwin, breeze, ...) with
  # nothing else ready to build alongside it -- so that single job
  # only ever got 4 of this CPU's 8 logical cores (all landing on the
  # 4 P-cores specifically; Linux's hybrid scheduler fills P-cores
  # before spilling to E-cores), leaving the 4 E-cores idle for the
  # whole build. max-jobs=1 / cores=8 gives a single job the entire
  # machine instead. Trade-off: if two mid-size derivations ever do
  # become ready at once again, they'll now serialize instead of
  # overlapping -- accepted, since that's been the rarer case lately.
  nix.settings.max-jobs = 1;
  nix.settings.cores = 8;

  # Compressed RAM-backed swap -- the actual OOM safety net for the
  # parallelism above. The only swap that existed before this was a
  # plain 2GB disk partition (/dev/nvme0n1p6, set up by the installer,
  # not managed here) -- thin headroom for concurrent Qt/KDE compiles,
  # which can spike a single compiler process well past a gigabyte.
  # zram absorbs those spikes via fast in-memory compression (no disk
  # I/O) rather than the kernel OOM-killer taking out a build (or
  # worse, something else) when RAM runs tight. 50% of RAM as the
  # uncompressed swap budget (roughly ~7.5GB here) -- real usable
  # capacity ends up higher after compression for typical memory
  # pages, without committing to a fixed size that could itself run
  # this laptop low on RAM for the compressed data.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Dedicated hibernation swap -- a new 16GB partition (nvme0n1p8),
  # carved out of freed space from shrinking the Windows partition.
  # zram above can't serve this role: it's backed by RAM itself, so its
  # contents vanish the instant power is cut, which is exactly what
  # hibernation needs to survive. This needs to be a real, persistent,
  # disk-backed area at least as big as RAM (15GB here) to hold a full
  # memory image. No priority set, matching the existing disk swap
  # entry in hardware-configuration.nix -- everyday swap pressure still
  # goes to zram first; this partition is really only meant to be
  # written to right before a hibernate.
  swapDevices = [
    { device = "/dev/disk/by-uuid/e77618dc-1791-4723-bd7e-292617b45362"; }
  ];

  # Points systemd-hibernate-resume (boot.initrd.systemd.enable above)
  # at the hibernation swap partition, so a resume image left there by
  # a previous hibernate is found and restored on the next boot.
  boot.resumeDevice = "/dev/disk/by-uuid/e77618dc-1791-4723-bd7e-292617b45362";

  # Secure Boot via lanzaboote. It builds on top of systemd-boot, so
  # systemd-boot itself stays "enabled" for its generation-management
  # options, but its own bootloader install step is disabled in favor
  # of lanzaboote's signed one.
  boot.loader.systemd-boot = {
    enable = false;
    configurationLimit = 3; # keep only the 3 latest generations in /boot
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 3;
  };

  boot.initrd.systemd.enable = true;
  boot.plymouth.enable = true;
}
