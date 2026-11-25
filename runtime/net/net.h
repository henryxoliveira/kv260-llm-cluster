// net.h — inter-board networking helpers (starter).
//
// Networking lives on the ARM side using plain Linux TCP sockets (see CLAUDE.md
// for why not in fabric). At batch 1 the messages between boards are tiny
// (one activation vector, a few KB), so per-message *latency* matters far more
// than bandwidth. TCP_NODELAY is set to stop Nagle's algorithm from holding
// small writes back to batch them.
//
// TODO (Phase 3+): pipeline-parallel send/recv of activations; later,
// all-reduce / all-gather for tensor parallelism.
#ifndef KVLLM_NET_H
#define KVLLM_NET_H

#include <stddef.h>
#include <stdint.h>

// Listen on `port` and block until one peer connects. Returns a socket fd, or -1.
int net_listen_accept(uint16_t port);

// Connect to host:port, retrying until it succeeds or `timeout_ms` passes. Returns fd or -1.
int net_connect(const char *host, uint16_t port, int timeout_ms);

// send()/recv() may transfer fewer bytes than asked. These loop until all `len`
// bytes are moved. Return 0 on success, -1 on error / peer closed.
int net_send_all(int fd, const void *buf, size_t len);
int net_recv_all(int fd, void *buf, size_t len);

void net_close(int fd);

#endif
