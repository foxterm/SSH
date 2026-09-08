#include "socket.h"

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

/* 为 socket 设置 SO_NOSIGPIPE，防止 App 在写已断开 socket 时崩溃 */
static void set_nosigpipe(int fd) {
  int optval = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &optval, sizeof(optval));
}

/* 带有超时控制的非阻塞 connect 实现 */
static int connect_with_timeout(int fd, const struct sockaddr *addr,
                                socklen_t addrlen, int timeout_ms) {
  if (timeout_ms <= 0) {
    return connect(fd, addr, addrlen);
  }

  // 设置非阻塞
  if (etos_socket_set_blocking(fd, false) != 0) {
    return -1;
  }

  int ret = connect(fd, addr, addrlen);
  if (ret < 0 && errno != EINPROGRESS) {
    return -1;
  }

  if (ret == 0) {
    // 立即连接成功
    etos_socket_set_blocking(fd, true);
    return 0;
  }

  // 使用 select 监听写入事件以判断连接是否完成
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
    // 超时 (0) 或 出错 (<0)
    return -1;
  }

  // 检查是否有错误发生
  int error = 0;
  socklen_t len = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) < 0 || error != 0) {
    if (error != 0)
      errno = error;
    return -1;
  }

  // 恢复为阻塞模式
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
  hints.ai_family = AF_UNSPEC;     // 支持 IPv4 / IPv6
  hints.ai_socktype = SOCK_STREAM; // TCP

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
      break; // 连接成功
    }

    close(fd);
    fd = ETOS_INVALID_SOCKET;
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

  // 1. 先建立与代理服务器的连接
  int fd = etos_socket_connect(proxy_host, proxy_port, timeout_ms);
  if (fd < 0)
    return ETOS_INVALID_SOCKET;

  // 2. HTTP 代理握手 (CONNECT 模式)
  if (type == ETOS_PROXY_HTTP) {
    char req[512];
    int len = snprintf(req, sizeof(req),
                       "CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n\r\n",
                       target_host, target_port, target_host, target_port);

    if (etos_socket_send_timeout(fd, req, len, 0, timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    char resp[256] = {0};
    if (etos_socket_recv_timeout(fd, resp, sizeof(resp) - 1, 0, timeout_ms) <=
        0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    // 检查 HTTP 响应状态码是否为 200
    if (strstr(resp, " 200 ") == NULL && strstr(resp, " 200\r\n") == NULL) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }
    return fd;
  }

  // 3. SOCKS5 代理握手
  if (type == ETOS_PROXY_SOCKS5) {
    // 方法选择包 (No Auth 或 User/Pass)
    unsigned char auth_req[3] = {0x05, 0x01, (user && password) ? 0x02 : 0x00};
    if (etos_socket_send_timeout(fd, (char *)auth_req, 3, 0, timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    unsigned char auth_resp[2] = {0};
    if (etos_socket_recv_timeout(fd, (char *)auth_resp, 2, 0, timeout_ms) <=
            0 ||
        auth_resp[0] != 0x05) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    // 账号密码认证处理
    if (auth_resp[1] == 0x02) {
      if (!user || !password) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET;
      }

      size_t ulen = strlen(user), plen = strlen(password);
      unsigned char pass_req[512];
      pass_req[0] = 0x01; // 鉴权版本
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
      if (etos_socket_recv_timeout(fd, (char *)pass_resp, 2, 0, timeout_ms) <=
              0 ||
          pass_resp[1] != 0x00) {
        etos_socket_close(fd);
        return ETOS_INVALID_SOCKET; // 认证失败
      }
    } else if (auth_resp[1] != 0x00) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    // 发送目标请求 (支持域名请求)
    size_t target_len = strlen(target_host);
    unsigned char conn_req[300];
    conn_req[0] = 0x05; // SOCKS Version
    conn_req[1] = 0x01; // CMD: CONNECT
    conn_req[2] = 0x00; // Reserved
    conn_req[3] = 0x03; // ATYP: Domain Name
    conn_req[4] = (unsigned char)target_len;
    memcpy(&conn_req[5], target_host, target_len);

    unsigned short net_port = htons((unsigned short)target_port);
    memcpy(&conn_req[5 + target_len], &net_port, 2);

    if (etos_socket_send_timeout(fd, (char *)conn_req, 7 + target_len, 0,
                                 timeout_ms) <= 0) {
      etos_socket_close(fd);
      return ETOS_INVALID_SOCKET;
    }

    unsigned char conn_resp[10] = {0};
    if (etos_socket_recv_timeout(fd, (char *)conn_resp, 10, 0, timeout_ms) <=
            0 ||
        conn_resp[1] != 0x00) {
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
      return -1; // 0 为超时，<0 为错误
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
      return -1;
  }
  return etos_socket_recv(fd, buf, len, flags);
}

ssize_t etos_socket_send(int fd, const char *buf, size_t len, int flags) {
  ssize_t rc = send(fd, buf, len, flags);
  if (rc < 0) {
    return -errno;
  }
  return rc;
}

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
    return false; // 对端已优雅关闭
  }
  if (res < 0) {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return true; // 连接正常，无待读数据
    }
    return false; // 连接异常
  }
  return true; // 有数据可读，连接正常
}

int etos_socket_set_keepalive(int fd, bool enable, int idle_sec,
                              int interval_sec, int count) {
  int optval = enable ? 1 : 0;
  if (setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &optval, sizeof(optval)) < 0) {
    return -1;
  }

  if (enable) {
    // macOS/iOS 专用: TCP_KEEPALIVE 对应空闲时长
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
