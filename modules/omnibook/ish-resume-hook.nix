# Automatically recovers this laptop's Intel ISH (Integrated Sensor
# Hub) after every real system resume -- runs the same full
# unbind/reload sequence rotation-lock.nix's tray toggle uses manually,
# but unconditionally, every wake, since the actual problem this works
# around has nothing to do with rotation-lock at all.
#
# Root cause (confirmed by reading the actual kernel driver,
# drivers/hid/intel-ish-hid/ishtp-hid-client.c, upstream Linux): on a
# normal light suspend (s2idle, what this laptop's `systemctl suspend`
# uses -- confirmed via `dmesg`: "PM: suspend entry (s2idle)"), the ISH
# device stays in the D0i3 low-power state rather than fully powering
# off. The driver's own resume path for that case
# (hid_ishtp_cl_resume_handler) does nothing but wait on a flag and
# clear it -- it never re-requests HID reports or reinitializes
# anything, assuming the ISH firmware will just keep sending sensor
# reports on its own once woken. There's a full reinit path
# (hid_ishtp_cl_reset_handler -> hid_ishtp_cl_init) that would actually
# fix this, but it only runs for a *deeper* D3 resume, which s2idle
# never triggers.
#
# Confirmed live, repeatedly, the night this was written: after a real
# suspend/resume, the proximity sensor's IIO devices exist and the
# kernel modules are loaded, but `in_attention_input` freezes at
# whatever it last read before suspend and never updates again --
# exactly the "no active reinitialization ever happens" symptom this
# driver-source reading predicts. The bug is genuinely in the ISH
# firmware's own D0i3 resume behavior, not fixable from Linux driver
# config alone; forcing the full unbind/reload is the only host-side
# recovery found so far, so it runs on every resume rather than relying
# on the tray toggle happening to get clicked.
{ pkgs, ... }:
let
  ish = import ./ish-sensor-scripts.nix { inherit pkgs; };
in
{
  powerManagement.resumeCommands = ''
    ${ish.ishSuspend}
    ${ish.ishResume}
  '';

  # Scoped precisely to these two exact, content-addressed script
  # paths -- not a broad NOPASSWD grant. Nix store immutability means
  # this rule can't be tricked into running anything else by editing
  # the target file; a content change produces a different store path
  # and this rule would need to be rebuilt to match it. Also covers
  # rotation-lock.nix's own manual tray-toggle use of these same two
  # scripts, since importing ish-sensor-scripts.nix with identical
  # arguments always produces identical store paths.
  security.sudo.extraRules = [
    {
      users = [ "keimoger" ];
      commands = [
        {
          command = "${ish.ishSuspend}";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${ish.ishResume}";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
