{ pkgs, ... }:
{
  services.fprintd.enable = true;
  # Override libfprint with TOD (Touch OEM Driver) support, needed for
  # this laptop's fingerprint sensor.
  services.fprintd.package = pkgs.fprintd-tod;

  security.pam.services.sudo.fprintAuth = true;
  # This line has always been a no-op: the sddm NixOS module hardcodes
  # useDefaultRules=false for the "sddm" PAM service and substacks
  # straight into "login" instead, so per-service options set directly
  # on "sddm" (this one included) never take effect (confirmed live --
  # /etc/pam.d/sddm has no fprintd line). Fingerprint actually reaches
  # the SDDM greeter today via fprintAuth's own cascade default
  # (config.services.fprintd.enable) landing on "login", which "sddm"
  # substacks -- not because of this line. Left as-is (harmless,
  # already covered by the cascade); see the howdy block below for the
  # same issue, fixed for real.
  security.pam.services.sddm.fprintAuth = true;
  # security.pam.services.kde.fprintAuth = true;

  # Windows-Hello-style face auth. This hardware's "HP 9MP Camera" is
  # actually two separate uvcvideo streams behind one USB device: RGB
  # on /dev/video0/1 and a dedicated 8-bit-greyscale IR sensor on
  # /dev/video2/3 (confirmed via `v4l2-ctl --info`, card type "HP IR
  # Camera") — a real dual-sensor setup, not RGB-only. Howdy's own
  # default device_path is already /dev/video2, so no override needed.
  #
  # Like fprintAuth (default = config.services.fprintd.enable, not
  # false), Howdy's security.pam.services.<name>.howdy.enable defaults
  # to security.pam.howdy.enable, which itself defaults to
  # services.howdy.enable -- so enabling the service alone cascades
  # face auth onto every PAM service. Overridden to false below and
  # opted in per-service instead, to keep this to sudo + wherever
  # fingerprint already reaches (login, substacked by both the SDDM
  # greeter and console login -- see the sddm.fprintAuth comment above
  # for why "login" and not "sddm" is the service that actually
  # matters here).
  #
  # control = "sufficient" (matching fprintd, which is hardcoded
  # sufficient) so a successful face match alone unlocks -- consistent
  # with the fast-biometric-unlock posture already established here.
  # Upstream's own docs warn this is spoofable with a printed photo;
  # accepted for convenience, matching the existing fingerprint
  # tradeoff, not because the risk isn't real.
  services.howdy.enable = true;
  services.howdy.control = "sufficient";
  security.pam.howdy.enable = false;
  security.pam.services.sudo.howdy.enable = true;
  security.pam.services.login.howdy.enable = true;
  # KWin's screen locker (kscreenlocker) doesn't use "login"/"sddm" at
  # all -- it uses two PAM services of its own, split deliberately by
  # the plasma6 NixOS module: "kde" (must stay biometric-free, per an
  # upstream comment citing nixpkgs#239770 -- fingerprint auth on that
  # service can block password entry outright) and "kde-fingerprint"
  # (mkIf'd on fprintd being enabled, used only for the biometric
  # prompt). This is why the lock screen kept offering only fingerprint
  # even after the login/sudo wiring above: howdy was never on either
  # of these. Mirroring fprintd's placement -- kde-fingerprint only,
  # never kde.
  security.pam.services.kde-fingerprint.howdy.enable = true;
  security.pam.services.kde-fingerprint.rules.auth.howdy.order = 11350;

  # Measured average darkness on this camera during enrollment was
  # ~76-77 even with the IR emitter confirmed lit -- above the
  # default dark_threshold of 60. Raw frame captures off /dev/video2
  # showed real (if dim) structure in the first frame of a burst,
  # consistent with auto-exposure not having converged yet rather
  # than a genuinely broken/unlit sensor. Raised past the observed
  # value with headroom rather than tuned to the exact number, since
  # exact darkness will vary with room lighting.
  services.howdy.settings.video.dark_threshold = 90;

  # Both fprintd and howdy are "sufficient" and PAM stops at the first
  # sufficient success, so whichever comes first in the stack wins in
  # practice. NixOS's own module composition always places fprintd
  # before howdy (fixed order in the upstream pam.nix rule list,
  # confirmed live: fprintd order=11400, howdy order=11500), and since
  # fprintd's libfprint call blocks waiting for a finger touch, howdy
  # never even got a turn unless fprintd was left to time out first --
  # confirmed live, face auth only kicked in after ignoring the
  # fingerprint prompt until it expired. Wanted face preferred
  # everywhere it's wired up, so overriding this rule's order (each
  # auto-composed rule's order is only lib.mkDefault'd, so a plain
  # assignment wins) to put howdy ahead of fprintd on every service
  # that has both.
  security.pam.services.login.rules.auth.howdy.order = 11350;
  security.pam.services.sudo.rules.auth.howdy.order = 11350;

  # The IR sensor needs its illuminator explicitly turned on via a
  # vendor-specific control command on most laptops -- this service
  # detects and persists that command. Device defaults to video2,
  # matching the IR node above. Run `sudo linux-enable-ir-emitter
  # configure` once after rebooting to actually probe and save the
  # working command (interactive, must be run by the user).
  services.linux-enable-ir-emitter.enable = true;

  # This only needs to run once per boot/resume (it's triggered by
  # suspend/hibernate targets too, see the unit's own After=/WantedBy=)
  # -- it's already successfully on for the running session.
  #
  # restartIfChanged=false alone wasn't enough (still failed on the
  # next switch after this was added) -- it only skips restarting a
  # unit that's currently *active*. Once the vendor UVC control write
  # fails once, the unit sits in "failed" (i.e. inactive) state, and
  # the *next* switch sees "this should be up per WantedBy= but isn't"
  # and starts it fresh -- a plain start, not a restart, so that flag
  # never applies once it's failed even a single time. Kept anyway
  # since it's harmless and still correct for a currently-active unit.
  #
  # The saved state at /var/lib/linux-enable-ir-emitter already shows
  # the "on" instruction as the device's current value -- it's already
  # correctly enabled from whenever it last actually succeeded. This
  # failure is the tool trying to redundantly re-apply that same
  # already-set value and having the hardware reject the write (a
  # known class of flakiness with vendor UVC extension-unit controls,
  # not a real functional problem) -- no CLI flag exists to make the
  # tool skip an already-applied value (checked --help), so rather
  # than patch a compiled Go binary for this, exit code 1 is just
  # accepted as this unit's definition of success.
  systemd.services.linux-enable-ir-emitter = {
    restartIfChanged = false;
    serviceConfig.SuccessExitStatus = [ 1 ];
  };
}
