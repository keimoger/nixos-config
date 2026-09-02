{ pkgs, ... }:
{
  time.timeZone = "Asia/Yerevan";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "hy_AM";
    LC_IDENTIFICATION = "hy_AM";
    LC_MEASUREMENT = "hy_AM";
    LC_MONETARY = "hy_AM";
    LC_NAME = "hy_AM";
    LC_NUMERIC = "hy_AM";
    LC_PAPER = "hy_AM";
    LC_TELEPHONE = "hy_AM";
    LC_TIME = "hy_AM";
  };

  # Plover's plover_uinput extension falls back to a Ctrl+Shift+U hex
  # -codepoint sequence for any character missing from the active
  # keyboard layout's scancode table — literally "through iBus" per
  # its own source comment. With PLOVER_UINPUT_LAYOUT defaulting to us
  # (fixed elsewhere, so English steno output isn't corrupted), every
  # Cyrillic letter typed via the Russian Firebird system takes this
  # fallback path. No ibus daemon was running and GTK_IM_MODULE/
  # QT_IM_MODULE/XMODIFIERS were all unset, so nothing was listening
  # for that sequence — it leaked through as literal keystrokes
  # instead of being consumed, which is what showed up as garbage.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
  };

  console = {
    enable = true;
    font = "ter-v32b"; # clean 32px font suitable for high-DPI screens
    packages = [ pkgs.terminus_font ];
    useXkbConfig = true; # inherit keyboard layout from xserver config
  };
}
