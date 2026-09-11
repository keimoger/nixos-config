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
  # 2 jobs x 4 cores each keeps the same worst-case total thread count
  # as the old 1-job setup would've had access to (up to 8), but
  # spreads it across two derivations instead of letting one giant
  # compile (e.g. a single heavy Qt/KDE package) claim every core and
  # a correspondingly large slice of RAM at once -- lets independent
  # small derivations (there were dozens queued up when this got
  # tuned, see the plasma-*.drv pile from the cursor-accel rebuild)
  # actually build concurrently instead of strictly serialized.
  nix.settings.max-jobs = 2;
  nix.settings.cores = 4;

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
