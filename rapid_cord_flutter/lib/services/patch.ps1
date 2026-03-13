$path = 'c:\rapid_cord\flutter-webrtc\windows\flutter_webrtc_plugin.cc'
$content = Get-Content $path -Raw

$pattern = '(?s)static DWORD WINAPI DuckPreventionThreadProc\(LPVOID\) \{.*?return 0;\s*\}'

$newProc = @'
static DWORD WINAPI DuckPreventionThreadProc(LPVOID) {
  if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) return 0;

  IMMDeviceEnumerator* enumerator = nullptr;
  CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&enumerator));
  if (!enumerator) { CoUninitialize(); return 0; }

  DuckPreventionCallback* duck_cb = new DuckPreventionCallback();
  std::vector<IAudioSessionManager2*> duck_mgrs;

  struct DummyStream {
      IAudioClient* client;
      IAudioSessionControl2* control;
  };
  std::vector<DummyStream> dummy_streams;

  struct NotifPair { IAudioSessionManager2* mgr; DuckingOptOutNotification* cb; };
  std::vector<NotifPair> notif_registrations;

  IMMDeviceCollection* col = nullptr;
  if (SUCCEEDED(enumerator->EnumAudioEndpoints(eAll, DEVICE_STATE_ACTIVE, &col))) {
      UINT n = 0; col->GetCount(&n);
      for (UINT i = 0; i < n; i++) {
          IMMDevice* dev = nullptr;
          if (FAILED(col->Item(i, &dev))) continue;

          // 1. Register DuckNotification on this device
          IAudioSessionManager2* mgr = nullptr;
          if (SUCCEEDED(dev->Activate(__uuidof(IAudioSessionManager2), CLSCTX_INPROC_SERVER, nullptr, (void**)&mgr))) {
              if (SUCCEEDED(mgr->RegisterDuckNotification(nullptr, duck_cb))) {
                  duck_mgrs.push_back(mgr);
                  mgr->AddRef(); 
              }
              // 2. Register Session Creation Notification
              auto* notif = new DuckingOptOutNotification();
              if (SUCCEEDED(mgr->RegisterSessionNotification(notif))) {
                  notif_registrations.push_back({mgr, notif});
                  mgr->AddRef();
                  notif->AddRef();
              }
              notif->Release();
              mgr->Release();
          }

          // 3. Create dummy stream to pre-occupy the session ducking policy
          IAudioClient* client = nullptr;
          if (SUCCEEDED(dev->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&client))) {
              WAVEFORMATEX* format = nullptr;
              if (SUCCEEDED(client->GetMixFormat(&format))) {
                  if (SUCCEEDED(client->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, format, nullptr))) {
                      IAudioSessionControl2* control = nullptr;
                      if (SUCCEEDED(client->GetService(__uuidof(IAudioSessionControl2), (void**)&control))) {
                          control->SetDuckingPreference(TRUE);
                          // We MUST call Start() so Windows registers it as an active communications stream!
                          client->Start();
                          dummy_streams.push_back({client, control});
                      }
                  }
                  CoTaskMemFree(format);
              }
              if (dummy_streams.empty() || dummy_streams.back().client != client) {
                  client->Release();
              }
          }
          dev->Release();
      }
      col->Release();
  }

  ScanAndOptOutAllSessions(enumerator);

  WaitForSingleObject(g_duck_thread_stop, INFINITE);

  for (auto& ds : dummy_streams) {
      ds.client->Stop();
      ds.control->Release();
      ds.client->Release();
  }
  for (auto& p : notif_registrations) {
      p.mgr->UnregisterSessionNotification(p.cb);
      p.cb->Release();
      p.mgr->Release();
  }
  for (auto* mgr : duck_mgrs) {
      mgr->UnregisterDuckNotification(duck_cb);
      mgr->Release();
  }
  duck_cb->Release();
  
  enumerator->Release();
  CoUninitialize();
  return 0;
}
'@

$content = [System.Text.RegularExpressions.Regex]::Replace($content, $pattern, $newProc)
Set-Content $path $content
