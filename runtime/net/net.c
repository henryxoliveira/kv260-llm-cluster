// net.c — see net.h.
#define _POSIX_C_SOURCE 200809L
#include "net.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static void set_nodelay(int fd) {
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
}

int net_listen_accept(uint16_t port) {
    int listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) return -1;

    int one = 1;  // allow quick restarts without "address already in use"
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(listen_fd, 1) < 0) {
        perror("net_listen_accept");
        close(listen_fd);
        return -1;
    }
    int fd = accept(listen_fd, NULL, NULL);
    close(listen_fd);
    if (fd >= 0) set_nodelay(fd);
    return fd;
}

int net_connect(const char *host, uint16_t port, int timeout_ms) {
    char port_str[8];
    snprintf(port_str, sizeof(port_str), "%u", port);

    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port_str, &hints, &res) != 0) return -1;

    int fd = -1;
    for (int waited_ms = 0; waited_ms <= timeout_ms; waited_ms += 100) {
        fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (fd >= 0 && connect(fd, res->ai_addr, res->ai_addrlen) == 0) break;
        if (fd >= 0) close(fd);
        fd = -1;
        struct timespec delay = {0, 100 * 1000 * 1000};  // peer may not be up yet; retry
        nanosleep(&delay, NULL);
    }
    freeaddrinfo(res);
    if (fd >= 0) set_nodelay(fd);
    return fd;
}

int net_send_all(int fd, const void *buf, size_t len) {
    const uint8_t *p = buf;
    while (len > 0) {
        ssize_t n = send(fd, p, len, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

int net_recv_all(int fd, void *buf, size_t len) {
    uint8_t *p = buf;
    while (len > 0) {
        ssize_t n = recv(fd, p, len, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;  // 0 = peer closed the connection
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

void net_close(int fd) {
    if (fd >= 0) close(fd);
}
