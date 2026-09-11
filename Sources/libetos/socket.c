#include "socket.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <openssl/bio.h>
#include <openssl/buffer.h>
#include <openssl/evp.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

/* ------------------------------------------------------------
   内部辅助函数
   ------------------------------------------------------------ */
/* 设置 SO_NOSIGPIPE 防止写入已断开 socket 导致进程崩溃 */
static void set_nosigpipe(int fd) {
#ifdef SO_NOSIGPIPE
  int optval = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &optval, sizeof(optval));
#else
  (void)fd;
#endif
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
    etos_socket_set_blocking(fd, true);
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
    etos_socket_set_blocking(fd, true);
    return -1;
  }

  int error = 0;
  socklen_t len = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) < 0 || error != 0) {
    if (error != 0)
      errno = error;
    etos_socket_set_blocking(fd, true);
    return -1;
  }

  etos_socket_set_blocking(fd, true);
  return 0;
}

/* 地址解析公共转换函数 */
static int extract_sockaddr_info(const struct sockaddr_storage *addr,
                                 char *ip_buf, size_t ip_buf_len, int *port) {
  if (addr->ss_family == AF_INET) {
    struct sockaddr_in *s = (struct sockaddr_in *)addr;
    *port = ntohs(s->sin_port);
    if (inet_ntop(AF_INET, &s->sin_addr, ip_buf, ip_buf_len) == NULL) {
      return -1;
    }
  } else if (addr->ss_family == AF_INET6) {
    struct sockaddr_in6 *s = (struct sockaddr_in6 *)addr;
    *port = ntohs(s->sin6_port);
    if (inet_ntop(AF_INET6, &s->sin6_addr, ip_buf, ip_buf_len) == NULL) {
      return -1;
    }
  } else {
    return -1; // 不支持的地址族
  }
  return 0;
}

/* Base64 编码 (由调用方使用 free() 释放内存) */
char *etos_base64_encode(const char *input) {
  if (!input)
    return NULL;
  BIO *b64 = BIO_new(BIO_f_base64());
  BIO *mem = BIO_new(BIO_s_mem());
  BIO_push(b64, mem);
  BIO_set_flags(b64, BIO_FLAGS_BASE64_NO_NL);
  BIO_write(b64, input, (int)strlen(input));
  BIO_flush(b64);
  BUF_MEM *ptr;
  BIO_get_mem_ptr(mem, &ptr);
  char *out = (char *)malloc(ptr->length + 1);
  if (out) {
    memcpy(out, ptr->data, ptr->length);
    out[ptr->length] = '\0';
  }
  BIO_free_all(b64);
  return out;
}

/* HTTP CONNECT 代理握手 (包含 Basic 认证与严格响应判断) */
static bool handshake_http_proxy(int fd, const char *target_host,
                                 int target_port, const char *user,
                                 const char *password, int timeout_ms) {
  if (!target_host || target_port <= 0 || target_port > 65535) {
    return false;
  }

  char req[1024];
  int len = 0;

  /* 1. 构建 Basic 认证 Header (如果有用户名密码) */
  char auth_header[512] = "";
  if (user && password && user[0] != '\0') {
    char auth_raw[256];
    snprintf(auth_raw, sizeof(auth_raw), "%s:%s", user, password);
    char *auth_b64 = etos_base64_encode(auth_raw);
    if (auth_b64) {
      snprintf(auth_header, sizeof(auth_header),
               "Proxy-Authorization: Basic %s\r\n", auth_b64);
      free(auth_b64);
    }
  }

  /* 2. 区分 IPv6 / IPv4 构建 CONNECT 请求 */
  struct in6_addr dummy_v6;
  if (inet_pton(AF_INET6, target_host, &dummy_v6) == 1) {
    len = snprintf(req, sizeof(req),
                   "CONNECT [%s]:%d HTTP/1.1\r\n"
                   "Host: [%s]:%d\r\n"
                   "%s\r\n",
                   target_host, target_port, target_host, target_port,
                   auth_header);
  } else {
    len = snprintf(req, sizeof(req),
                   "CONNECT %s:%d HTTP/1.1\r\n"
                   "Host: %s:%d\r\n"
                   "%s\r\n",
                   target_host, target_port, target_host, target_port,
                   auth_header);
  }

  if (len < 0 || len >= (int)sizeof(req) ||
      etos_socket_send_timeout(fd, req, len, 0, timeout_ms) <= 0) {
    return false;
  }

  /* 3. 接收并读取 HTTP 响应头 */
  char resp[2048];
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

  if (!header_complete) {
    return false;
  }

  /* 4. 严格校验响应首行状态码是否为 200 */
  if (strncasecmp(resp, "HTTP/1.0 200", 12) == 0 ||
      strncasecmp(resp, "HTTP/1.1 200", 12) == 0) {
    return true;
  }

  return false;
}

/* SOCKS5 代理握手 */
static bool handshake_socks5_proxy(int fd, const char *target_host,
                                   int target_port, const char *user,
                                   const char *password, int timeout_ms) {
  if (!target_host || target_port <= 0 || target_port > 65535) {
    return false;
  }

  /* ---------------- Step 1: 方法协商 ---------------- */
  unsigned char auth_req[3];
  auth_req[0] = 0x05; // SOCKS Version
  auth_req[1] = 0x01; // 方法数量: 1
  auth_req[2] = (user && password && user[0] != '\0')
                    ? 0x02
                    : 0x00; // 0x02: 账号密码, 0x00: 匿名

  if (etos_socket_send_timeout(fd, (char *)auth_req, 3, 0, timeout_ms) <= 0) {
    return false;
  }

  unsigned char auth_resp[2] = {0};
  if (!recv_exact(fd, auth_resp, 2, timeout_ms) || auth_resp[0] != 0x05) {
    return false;
  }

  /* ---------------- Step 2: 账号密码认证 (若代理要求 0x02) ---------------- */
  if (auth_resp[1] == 0x02) {
    if (!user || !password)
      return false;

    size_t ulen = strlen(user);
    size_t plen = strlen(password);
    if (ulen > 255 || plen > 255)
      return false;

    unsigned char pass_req[512];
    size_t pass_len = 0;
    pass_req[pass_len++] = 0x01; // 账号密码子协议版本
    pass_req[pass_len++] = (unsigned char)ulen;
    memcpy(&pass_req[pass_len], user, ulen);
    pass_len += ulen;
    pass_req[pass_len++] = (unsigned char)plen;
    memcpy(&pass_req[pass_len], password, plen);
    pass_len += plen;

    if (etos_socket_send_timeout(fd, (char *)pass_req, pass_len, 0,
                                 timeout_ms) <= 0) {
      return false;
    }

    unsigned char pass_resp[2] = {0};
    if (!recv_exact(fd, pass_resp, 2, timeout_ms) || pass_resp[1] != 0x00) {
      return false; // 账号密码校验失败
    }
  } else if (auth_resp[1] != 0x00) {
    return false; // 代理拒绝了协商的认证方式
  }

  /* ---------------- Step 3: 发送 CONNECT 请求 ---------------- */
  unsigned char conn_req[300];
  size_t p = 0;

  conn_req[p++] = 0x05; // VER: SOCKS5
  conn_req[p++] = 0x01; // CMD: CONNECT
  conn_req[p++] = 0x00; // RSV: 保留字段

  struct in_addr addr4;
  struct in6_addr addr6;

  if (inet_pton(AF_INET, target_host, &addr4) == 1) {
    conn_req[p++] = 0x01; // ATYP: IPv4 (4 字节)
    memcpy(&conn_req[p], &addr4, 4);
    p += 4;
  } else if (inet_pton(AF_INET6, target_host, &addr6) == 1) {
    conn_req[p++] = 0x04; // ATYP: IPv6 (16 字节)
    memcpy(&conn_req[p], &addr6, 16);
    p += 16;
  } else {
    size_t target_len = strlen(target_host);
    if (target_len > 255)
      return false;
    conn_req[p++] = 0x03; // ATYP: Domain (1 字节长度 + N 字节域名)
    conn_req[p++] = (unsigned char)target_len;
    memcpy(&conn_req[p], target_host, target_len);
    p += target_len;
  }

  // 写入目标端口 (网络大端序)
  unsigned short net_port = htons((unsigned short)target_port);
  memcpy(&conn_req[p], &net_port, 2);
  p += 2;

  if (etos_socket_send_timeout(fd, (char *)conn_req, p, 0, timeout_ms) <= 0) {
    return false;
  }

  /* ---------------- Step 4: 读取并解析 CONNECT 响应 ---------------- */
  unsigned char head[4];
  if (!recv_exact(fd, head, 4, timeout_ms)) {
    return false;
  }

  if (head[0] != 0x05 || head[1] != 0x00) {
    // head[1] 是 REP 状态码，0x00 才是 Success。常见的有 0x01 (普通失败)、0x02
    // (规则不允许)、0x04 (主机不可达) 等
    return false;
  }

  /* ---------------- Step 5: 清理 BND.ADDR / BND.PORT 缓冲区 ----------------
   */
  size_t skip_bytes = 0;
  if (head[3] == 0x01) { // IPv4
    skip_bytes = 4 + 2;
  } else if (head[3] == 0x04) { // IPv6
    skip_bytes = 16 + 2;
  } else if (head[3] == 0x03) { // Domain
    unsigned char dlen = 0;
    if (!recv_exact(fd, &dlen, 1, timeout_ms))
      return false;
    skip_bytes = (size_t)dlen + 2;
  } else {
    return false;
  }

  unsigned char dummy[260];
  if (!recv_exact(fd, dummy, skip_bytes, timeout_ms)) {
    return false;
  }

  return true;
}

/* ------------------------------------------------------------
   外部接口实现
   ------------------------------------------------------------ */
int etos_socket_get_traffic_stats(int fd, FdTrafficStats *stats) {
  if (fd < 0 || !stats) {
    return -1;
  }

  struct tcp_connection_info info;
  socklen_t len = sizeof(info);

  // 调用 Darwin 内核 TCP 统计 API
  if (getsockopt(fd, IPPROTO_TCP, TCP_CONNECTION_INFO, &info, &len) == 0) {
    // 原子操作赋值（兼顾多线程安全读取）
    atomic_store(&stats->rx_bytes, info.tcpi_rxbytes);
    atomic_store(&stats->tx_bytes, info.tcpi_txbytes);
    return 0;
  }

  return -1;
}

u_int64_t etos_stats_get_rx(const FdTrafficStats *stats) {
  if (!stats)
    return 0;
  return atomic_load(&stats->rx_bytes);
}

u_int64_t etos_stats_get_tx(const FdTrafficStats *stats) {
  if (!stats)
    return 0;
  return atomic_load(&stats->tx_bytes);
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
  etos_socket_set_nodelay(fd, true);
  etos_socket_set_keepalive(fd, true, 5, 5, 10);
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

  bool ok = false;
  if (type == ETOS_PROXY_HTTP) {
    ok = handshake_http_proxy(fd, target_host, target_port, user, password,
                              timeout_ms);
  } else if (type == ETOS_PROXY_SOCKS5) {
    ok = handshake_socks5_proxy(fd, target_host, target_port, user, password,
                                timeout_ms);
  }

  if (!ok) {
    etos_socket_close(fd);
    return ETOS_INVALID_SOCKET;
  }

  return fd;
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

ssize_t etos_socket_send(int fd, const char *buf, size_t len, int flags) {
  ssize_t rc = send(fd, buf, len, flags);
  return rc;
}

ssize_t etos_socket_recv(int fd, char *buf, size_t len, int flags) {
  ssize_t rc = recv(fd, buf, len, flags);
  return rc;
}

ssize_t libssh2_recv(int sock, void *buffer, size_t length, int flags) {
  ssize_t rc;

  rc = recv(sock, buffer, length, flags);
  if (rc < 0) {
    int err;
#ifdef _WIN32
    err = _libssh2_wsa2errno();
#else
    err = errno;
#endif
    /* Profiling tools that use SIGPROF can cause EINTR responses.
       recv() does not modify its arguments when it returns EINTR,
       but there may be data waiting, so the caller should try again */
    if (err == EINTR)
      return -EAGAIN;
    /* Sometimes the first recv() function call sets errno to ENOENT on
       Solaris and HP-UX */
    if (err == ENOENT)
      return -EAGAIN;
#ifdef EWOULDBLOCK /* For VMS and other special unixes */
    else if (err == EWOULDBLOCK)
      return -EAGAIN;
#endif
    else
      return -err;
  }
  return rc;
}

/* _libssh2_send
 *
 * Replacement for the standard send, return -errno on failure.
 */
ssize_t libssh2_send(int sock, const void *buffer, size_t length, int flags) {
  ssize_t rc;

  rc = send(sock, buffer, length, flags);
  if (rc < 0) {
    int err;
#ifdef _WIN32
    err = _libssh2_wsa2errno();
#else
    err = errno;
#endif
    /* Profiling tools that use SIGPROF can cause EINTR responses.
       send() is defined as not yet sending any data when it returns EINTR,
       so the caller should try again */
    if (err == EINTR)
      return -EAGAIN;
#ifdef EWOULDBLOCK /* For VMS and other special unixes */
    if (err == EWOULDBLOCK)
      return -EAGAIN;
#endif
    return -err;
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

int etos_socket_last_error(void) { return errno; }

const char *etos_socket_strerror(int errnum) { return strerror(errnum); }

/* 获取远端 (Server) IP 和端口 */
int etos_socket_get_peer_info(int fd, char *ip_buf, size_t ip_buf_len,
                              int *port) {
  if (fd < 0 || !ip_buf || ip_buf_len == 0 || !port) {
    return -1;
  }

  struct sockaddr_storage addr;
  socklen_t addr_len = sizeof(addr);

  if (getpeername(fd, (struct sockaddr *)&addr, &addr_len) < 0) {
    return -1;
  }

  return extract_sockaddr_info(&addr, ip_buf, ip_buf_len, port);
}

/* 获取本地 (Client) IP 和端口 */
int etos_socket_get_local_info(int fd, char *ip_buf, size_t ip_buf_len,
                               int *port) {
  if (fd < 0 || !ip_buf || ip_buf_len == 0 || !port) {
    return -1;
  }

  struct sockaddr_storage addr;
  socklen_t addr_len = sizeof(addr);

  if (getsockname(fd, (struct sockaddr *)&addr, &addr_len) < 0) {
    return -1;
  }

  return extract_sockaddr_info(&addr, ip_buf, ip_buf_len, port);
}
