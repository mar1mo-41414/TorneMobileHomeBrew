// Native AKE socket hub for Windows: registers the
// com.markun.tmhb/ake_socket method channel and the
// com.markun.tmhb/ake_socket_events event channel on the runner's
// binary messenger.
//
// This is the Windows counterpart of linux/runner/ake_socket.h
// (and of the Swift AkeSocketHub on iOS/macOS and the Kotlin hub on
// Android): the fifth implementation of the same channel contract.
#ifndef RUNNER_AKE_SOCKET_H_
#define RUNNER_AKE_SOCKET_H_

#include <flutter/plugin_registrar.h>
#include <windows.h>

// Window message that carries work from the AKE worker threads back
// to the UI (platform) thread. Flutter's Windows channels and event
// sink may only be touched on the platform thread, and the platform
// thread is the thread running this window's message loop, so worker
// threads hand their results over with PostMessage — the Win32
// analogue of the Linux hub posting to the GLib main loop with
// g_idle_add and of the Swift hub dispatching to the main queue.
// FlutterWindow::MessageHandler routes this message to
// AkeSocketHandleMessage before anything else sees it.
inline constexpr UINT kAkeSocketMessage = WM_APP + 0xA1E;

// Registers the AKE socket channels. Call once from
// FlutterWindow::OnCreate, after RegisterPlugins, with the
// registrar for a plugin name of our own and the top-level window
// handle (used as the PostMessage target for worker threads).
void AkeSocketRegister(flutter::PluginRegistrar* registrar,
                       HWND window_handle);

// Dispatches one kAkeSocketMessage posted by an AKE worker thread.
// Runs on the UI thread (called from FlutterWindow::MessageHandler).
// Returns true if |message| was the AKE message and has been handled.
bool AkeSocketHandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

#endif  // RUNNER_AKE_SOCKET_H_
