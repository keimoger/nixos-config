{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General = {
      Experimental = true; # shows battery levels for connected peripherals
      FastConnectable = true; # enables automatic connection to known devices
    };
  };

  # Using KDE's own Bluetooth applet instead of blueman.
  services.blueman.enable = false;

  environment.systemPackages = with pkgs; [
    kdePackages.bluedevil # official KDE Plasma 6 Bluetooth applet
    bluez
    bluez-tools
  ];
}
