# Kinetic/inertial scrolling for mouse wheels, via libinput's Lua plugin
# system (added in libinput 1.30). KWin's own libinput backend already
# calls libinput_plugin_system_load_plugins() unconditionally on startup
# (confirmed directly in src/backends/libinput/context.cpp) -- no opt-in
# flag or libinput rebuild needed, just a file in the right place.
#
# Plugins load from /etc/libinput/plugins/*.lua in ascending sort order.
# See ./scroll-inertia.lua for the actual momentum/decay logic.
{ ... }:
{
  environment.etc."libinput/plugins/50-scroll-inertia.lua".source = ./scroll-inertia.lua;
}
