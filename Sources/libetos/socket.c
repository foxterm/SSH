#include "socket.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

/* ------------------------------------------------------------
   内部辅助函数
   ------------------------------------------------------------ */

/* 设置 SO_NOSIGPIPE 防止写入已断开 socket 导致进程崩溃 */
static void set_nosigpipe(int fd) {
  int optval = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &optval, sizeof(optval));
}

/* 专用于代理握手的严格读取辅助函数 */
static bool recv_exact(int fd, void *buf, size_t len, int timeout_ms) {
  size_t total_read = 0;
  char *ptr = (char *)buf;

  while (total_read < len) {
    ssize_t rc = etos_socket_recv_timeout(fd, ptr + total_read,
                                          len - total_read, 0, timeout_ms);
    if (rc <= 0) { // rc < 0 (-errno) 或 rc == 0 (断开)
      return false;
    }
    total_read += rc;
  }
  return true;
}

static int connect_with_timeout(int fd, const struct sockaddr *addr,
                                socklen_t addrlen, int timeout_ms) {
  if (timeout_ms <= 0) {
    return connect(fd, addr, addrlen);
  }

  if (etos_socket_set_blocking(fd, false) != 0) {
    return -1;
  }

  int ret = connect(fd, addr, addrlen);
  if (ret < 0 && errno != EINPROGRESS) {
    return -1;
  }

  if (ret == 0) {
    etos_socket_set_blocking(fd, true);
    return 0;
  }

  fd_set wset, eset;
  FD_ZERO(&wset);
  FD_ZERO(&eset);
  FD_SET(fd, &wset);
  FD_SET(fd, &eset);

  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;

  ret = select(fd + 1, NULL, &wset, &eset, &tv);
  if (ret <= 0) {
    return -1;
  }

  int error = 0;
  socklen_t len = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) < 0 || error != 0) {
    if (error != 0)
      errno = error;
    return -1;
  }

  etos_socket_set_blocking(fd, true);
  return 0;
}

/* ------------------------------------------------------------
   外部接口实现
   ------------------------------------------------------------ */

int etos_socket_connect(const char *host, int port, int timeout_ms) {
  if (!host || port <= 0 || port > 65535)
    return ETOS_INVALID_SOCKET;

  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  struct addrinfo hints, *res = NULL, *rp = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC; // 自动支持 IPv4 和 IPv6
  hints.ai_socktype = SOCK_STREAM;

  if (getaddrinfo(host, port_str, &hints, &res) != 0) {
    return ETOS_INVALID_SOCKET;
  }

  int fd = ETOS_INVALID_SOCKET;
  for (rp = res; rp != NULL; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd < 0)
      continue;

    set_nosigpipe(fd);

    if (connect_with_timeout(fd, rp->ai_addr, rp->ai_addrlen, timeout_ms) ==
        0) {
      break; // 连接成功，保留该 fd 并退出循环
    }

    close(fd);
    fd = ETOS_INVALID_SOCKET; // 尝试下一个解析出的 IP 地址
  }

  freeaddrinfo(res);
  return fd;
}

int etos_socket_connect_proxy(int type, const char *proxy_host, int proxy_port,
                              int timeout_ms, const char *target_host,
                              int target_port, const char *user,
                              const char *password) {
  if (type == ETOS_PROXY_NONE) {
    return etos_socket_connect(target_host, target_port, timeout_ms);
  }

  int fd = etos_socket_connect(proxy_host, proxy_port, timeout_ms);
  if (fd < 0)
    return ETOS_INVALID_SOCKET;

  /* ---------------- HTTP PROXY ---------------- */
  if (type == ETOS_PROXY_HTTP) {
    char req[512];
    int len;

    // 判断目标 host 是否为 IPv6 字面量 (例如 "::1")
    struct in6_addr dummy_v6;
    if (inet_pton(AF_INET6, target_host, &dummy_v6) == 1) {
      // IPv6 目标需要使用 [] 包裹格式
      len = snprintf(req, sizeof(req),
                     "CONNECT [%s]:%d HTTP/1.1\r\nHost: [%s]:%d\r\n\r\n",
                     target_host, target_port, target_host, target_port);
    } else {
      // IPv4 或 域名
      len = snprintf(req, sizeof(req),
                     "CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n",
                     target_host, target_port, target_host, target_port);
    }

    if (len < 0 || len >= (int)sizeof(req) ||
        etos_socket_send_timeout(fd, req, len, 0, timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    char resp[1024];
    size_t resp_len = 0;
    bool header_complete = false;

    while (resp_len < sizeof(resp) - 1) {
      ssize_t rc = etos_socket_recv_timeout(
          fd, resp + resp_len, sizeof(resp) - 1 - resp_len, 0, timeout_ms);
      if (rc <= 0)
        break;
      resp_len += rc;
      resp[resp_len] = '\0';

      if (strstr(resp, "\r\n\r\n") != NULL) {
        header_complete = true;
        break;
      }
    }

    if (!header_complete ||
        (strstr(resp, " 200 ") == NULL && strstr(resp, " 200\r\n") == NULL)) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }
    return fd;
  }

  /* ---------------- SOCKS5 PROXY ---------------- */
  if (type == ETOS_PROXY_SOCKS5) {
    unsigned char auth_req[3] = {0x05, 0x01, (user && password) ? 0x02 : 0x00};
    if (etos_socket_send_timeout(fd, (char *)auth_req, 3, 0, timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    unsigned char auth_resp[2] = {0};
    if (!recv_exact(fd, auth_resp, 2, timeout_ms) || auth_resp[0] != 0x05) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    if (auth_resp[1] == 0x02) {
      if (!user || !password) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }

      size_t ulen = strlen(user), plen = strlen(password);
      if (ulen > 255 || plen > 255) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }

      unsigned char pass_req[512];
      pass_req[0] = 0x01;
      pass_req[1] = (unsigned char)ulen;
      memcpy(&pass_req[2], user, ulen);
      pass_req[2 + ulen] = (unsigned char)plen;
      memcpy(&pass_req[3 + ulen], password, plen);

      if (etos_socket_send_timeout(fd, (char *)pass_req, 3 + ulen + plen, 0,
                                   timeout_ms) <= 0) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }

      unsigned char pass_resp[2] = {0};
      if (!recv_exact(fd, pass_resp, 2, timeout_ms) || pass_resp[1] != 0x00) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }
    } else if (auth_resp[1] != 0x00) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    /* 校验目标地址类型并打包 CONNECT 请求 */
    unsigned char conn_req[300];
    size_t req_len = 0;

    conn_req[0] = 0x05; // VER: SOCKS5
    conn_req[1] = 0x01; // CMD: CONNECT
    conn_req[2] = 0x00; // RSV

    struct in_addr addr4;
    struct in6_addr addr6;

    if (inet_pton(AF_INET, target_host, &addr4) == 1) {
      /* 1. 目标为标准 IPv4 */
      conn_req[3] = 0x01; // ATYP: IPv4
      memcpy(&conn_req[4], &addr4, 4);
      req_len = 4 + 4;
    } else if (inet_pton(AF_INET6, target_host, &addr6) == 1) {
      /* 2. 目标为标准 IPv6 */
      conn_req[3] = 0x04; // ATYP: IPv6
      memcpy(&conn_req[4], &addr6, 16);
      req_len = 4 + 16;
    } else {
      /* 3. 目标为域名 Domain Name */
      size_t target_len = strlen(target_host);
      if (target_len > 255) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }
      conn_req[3] = 0x03; // ATYP: Domain
      conn_req[4] = (unsigned char)target_len;
      memcpy(&conn_req[5], target_host, target_len);
      req_len = 5 + target_len;
    }

    // 写入端口号 (大端序)
    unsigned short net_port = htons((unsigned short)target_port);
    memcpy(&conn_req[req_len], &net_port, 2);
    req_len += 2;

    if (etos_socket_send_timeout(fd, (char *)conn_req, req_len, 0,
                                 timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    /* 读取响应头 */
    unsigned char head[4];
    if (!recv_exact(fd, head, 4, timeout_ms) || head[1] != 0x00) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    /* 读取并清理代理服务端的绑字地址数据 (BND.ADDR + BND.PORT) */
    size_t skip_bytes = 0;
    if (head[3] == 0x01) { // IPv4: 4 字节 IP + 2 字节 Port
      skip_bytes = 4 + 2;
    } else if (head[3] == 0x04) { // IPv6: 16 字节 IP + 2 字节 Port
      skip_bytes = 16 + 2;
    } else if (head[3] ==
               0x03) { // Domain: 1 字节 长度 + len 字节名 + 2 字节 Port
      unsigned char dlen = 0;
      if (!recv_exact(fd, &dlen, 1, timeout_ms)) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }
      skip_bytes = dlen + 2;
    } else {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    unsigned char dummy[260];
    if (!recv_exact(fd, dummy, skip_bytes, timeout_ms)) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    return fd;
  }

  etos_socket_close(fd);
  return ETOS_INVALID_SOCKET;
}

ssize_t etos_socket_send_timeout(int fd, const char *buf, size_t len, int flags,
                                 int timeout_ms) {
  if (timeout_ms > 0) {
    fd_set wset;
    FD_ZERO(&wset);
    FD_SET(fd, &wset);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    int ret = select(fd + 1, NULL, &wset, NULL, &tv);
    if (ret <= 0)
      return -ETIMEDOUT;
  }
  return etos_socket_send(fd, buf, len, flags);
}

ssize_t etos_socket_recv_timeout(int fd, char *buf, size_t len, int flags,
                                 int timeout_ms) {
  if (timeout_ms > 0) {
    fd_set rset;
    FD_ZERO(&rset);
    FD_SET(fd, &rset);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    int ret = select(fd + 1, &rset, NULL, NULL, &tv);
    if (ret <= 0)
      return -ETIMEDOUT;
  }
  return etos_socket_recv(fd, buf, len, flags);
}

/* 适配 libssh2: 必须返回 -errno */
ssize_t etos_socket_send(int fd, const char *buf, size_t len, int flags) {
  ssize_t rc = send(fd, buf, len, flags);
  if (rc < 0) {
    return -errno;
  }
  return rc;
}

/* 适配 libssh2: 必须返回 -errno */
ssize_t etos_socket_recv(int fd, char *buf, size_t len, int flags) {
  ssize_t rc = recv(fd, buf, len, flags);
  if (rc < 0) {
    return -errno;
  }
  return rc;
}

int etos_socket_shutdown(int fd, int how) { return shutdown(fd, how); }

void etos_socket_close(int fd) {
  if (fd >= 0) {
    close(fd);
  }
}

int etos_socket_set_blocking(int fd, bool blocking) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0)
    return -1;

  if (blocking) {
    flags &= ~O_NONBLOCK;
  } else {
    flags |= O_NONBLOCK;
  }
  return fcntl(fd, F_SETFL, flags);
}

bool etos_socket_is_connect(int fd) {
  if (fd < 0)
    return false;

  char buf;
  ssize_t res = recv(fd, &buf, 1, MSG_PEEK | MSG_DONTWAIT);
  if (res == 0) {
    return false;
  }
  if (res < 0) {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return true;
    }
    return false;
  }
  return true;
}

int etos_socket_set_keepalive(int fd, bool enable, int idle_sec,
                              int interval_sec, int count) {
  int optval = enable ? 1 : 0;
  if (setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &optval, sizeof(optval)) < 0) {
    return -1;
  }

  if (enable) {
    if (idle_sec > 0) {
      setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle_sec, sizeof(idle_sec));
    }
    if (interval_sec > 0) {
      setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &interval_sec,
                 sizeof(interval_sec));
    }
    if (count > 0) {
      setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &count, sizeof(count));
    }
  }
  return 0;
}

int etos_socket_set_nodelay(int fd, bool enable) {
  int optval = enable ? 1 : 0;
  return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &optval, sizeof(optval));
}

int etos_socket_last_error(void) { return errno; }

const char *etos_socket_strerror(int errnum) { return strerror(errnum); }

int etos_socket_get_peer_info(int fd, char *ip_buf, size_t ip_buf_len,
                              int *port) {
  if (fd < 0 || !ip_buf || ip_buf_len == 0 || !port) {
    return -1;
  }

  struct sockaddr_storage addr;
  socklen_t addr_len = sizeof(addr);

  // 获取套接字连接的远端地址
  if (getpeername(fd, (struct sockaddr *)&addr, &addr_len) < 0) {
    return -1;
  }

  // 根据 IPv4 或 IPv6 进行解析
  if (addr.ss_family == AF_INET) {
    struct sockaddr_in *s = (struct sockaddr_in *)&addr;
    *port = ntohs(s->sin_port);
    if (inet_ntop(AF_INET, &s->sin_addr, ip_buf, ip_buf_len) == NULL) {
      return -1;
    }
  } else if (addr.ss_family == AF_INET6) {
    struct sockaddr_in6 *s = (struct sockaddr_in6 *)&addr;
    *port = ntohs(s->sin6_port);
    if (inet_ntop(AF_INET6, &s->sin6_addr, ip_buf, ip_buf_len) == NULL) {
      return -1;
    }
  } else {
    return -1; // 不支持的地址族
  }

  return 0;
}
