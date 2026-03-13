//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audioplayers_windows/audioplayers_windows_plugin.h>
#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <wireguard_flutter/wireguard_flutter_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioplayersWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioplayersWindowsPlugin"));
  DesktopMultiWindowPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
  FlutterWebRTCPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterWebRTCPlugin"));
  WireguardFlutterPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WireguardFlutterPluginCApi"));
}
