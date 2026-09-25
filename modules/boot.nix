{ ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Lets this user `nix copy` store paths built on the remote builder
  # (modules/remote-builder.nix) straight into the local store. Without
  # this, nix-daemon refuses them with "lacks a signature by a trusted
  # key" -- paths built elsewhere aren't signed by anything the daemon
  # already trusts, and only a trusted user is allowed to import
  # unsigned paths directly. Single-user laptop, so this is simpler
  # than setting up a real signing keypair (trusted-public-keys) for
  # what's effectively a one-machine trust boundary anyway.
  nix.settings.trusted-users = [ "keimoger" ];

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

  # Limine provides a graphical boot menu while retaining Secure Boot.
  # Lanzaboote is disabled here; its old signed systemd-boot installation
  # remains on the ESP as a recovery path until Limine has been verified.
  boot.loader.systemd-boot = {
    enable = false;
    configurationLimit = 3; # keep only the 3 latest generations in /boot
  };

  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = false;
    maxGenerations = 3;
    secureBoot.enable = true;
    # Keep the existing Windows installation available from Limine.
    extraEntries = ''
      /Windows
          protocol: efi_chainload
          image_path: boot():///EFI/Microsoft/Boot/bootmgfw.efi
    '';

    style = {
      interface = {
        branding = "keibook";
        brandingColor = "8AADF4";
        helpColor = "A6DA95";
        helpColorBright = "8BD5CA";
      };
      graphicalTerminal = {
        foreground = "CAD3F5";
        brightForeground = "FFFFFF";
        background = "CC24273A";
        brightBackground = "CC363A4F";
        margin = 32;
        marginGradient = 8;
      };
    };
  };

  # Keep the menu visible briefly without making every boot interactive.
  boot.loader.timeout = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = false;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 3;
  };

  boot.initrd.systemd.enable = true;
  boot.plymouth.enable = true;
}
