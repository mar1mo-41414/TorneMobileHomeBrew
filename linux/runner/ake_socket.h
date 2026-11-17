// Native AKE socket hub for Linux (plan 44.6): registers the
// com.markun.tmhb/ake_socket method channel and the
// com.markun.tmhb/ake_socket_events event channel on the runner's
// binary messenger.
#ifndef RUNNER_AKE_SOCKET_H_
#define RUNNER_AKE_SOCKET_H_

#include <flutter_linux/flutter_linux.h>

// Registers the AKE socket channels. Call once from the application
// activate handler, after the view (and its plugin registry) exists.
void ake_socket_register(FlPluginRegistry* registry);

#endif  // RUNNER_AKE_SOCKET_H_
