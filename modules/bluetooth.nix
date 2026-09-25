{ pkgs, ... }:
let
  bluez86Headers = pkgs.bluez-headers.overrideAttrs (_: {
    version = "5.86";
    src = pkgs.fetchurl {
      url = "mirror://kernel/linux/bluetooth/bluez-5.86.tar.xz";
      hash = "sha256-mfFEVAxgcFkeTFO8uXfrQmZMYrezbLNaKc9y3tM5Yh0=";
    };
  });
  bluez86 = (pkgs.bluez.override {
    bluez-headers = bluez86Headers;
  }).overrideAttrs (_: {
    # The current nixpkgs patches target BlueZ 5.87 and do not apply to the
    # 5.86 source; the upstream 5.86 source builds without them.
    patches = [ ];
  });
in
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    package = bluez86;
    settings.General = {
      # The experimental battery provider can issue repeated HID GET_REPORT
      # requests to Apple Magic Trackpads and destabilize their connection.
      Experimental = false;
      FastConnectable = true; # enables automatic connection to known devices
    };
  };

  # Using KDE's own Bluetooth applet instead of blueman.
  services.blueman.enable = false;

  environment.systemPackages = with pkgs; [
    kdePackages.bluedevil # official KDE Plasma 6 Bluetooth applet
    bluez86
    bluez-tools
  ];
}
