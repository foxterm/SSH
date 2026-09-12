#ifndef ETOS_SOCKET_H
#define ETOS_SOCKET_H
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 代理类型定义 */
#define ETOS_PROXY_NONE 0
#define ETOS_PROXY_SOCKS5 1
#define ETOS_PROXY_HTTP 2

/* 常规常量定义 */
#define ETOS_INVALID_SOCKET (-1)
/* ------------------------------------------------------------
   流量统计数据结构
   ------------------------------------------------------------ */
typedef struct {
  _Atomic u_int64_t rx_bytes; /* 接收总字节数 */
  _Atomic u_int64_t tx_bytes; /* 发送总字节数 */
  _Atomic u_int32_t rtt_us;   /* 当前实时往返时间（微秒，瞬时值） */
} FdTrafficStats;

/* ------------------------------------------------------------
   网络 I/O 服务 (macOS / iOS 专用)
   ------------------------------------------------------------ */
/**
 * 获取 Socket 当前累积的发送与接收流量（Apple 官方推荐姿势）
 * @param fd Socket 文件描述符
 * @param stats 输出结构体指针，用于接收字节统计
 * @return 成功返回 0，失败返回 -1 (例如非 TCP 套接字或已断开)
 */
int etos_socket_get_traffic_stats(int fd, FdTrafficStats *stats);

/**
 * 获取接收的字节数
 * @param stats 指向 FdTrafficStats 结构体的指针
 * @return 成功返回字节数，失败返回 -1
 * @note 该函数仅用于获取最新的统计信息，不会重置计数器。
 */
u_int64_t etos_stats_get_rx(const FdTrafficStats *stats);

/**
 * 获取发送的字节数
 * @param stats 指向 FdTrafficStats 结构体的指针
 * @return 成功返回字节数，失败返回 -1
 * @note 该函数仅用于获取最新的统计信息，不会重置计数器。
 */
u_int64_t etos_stats_get_tx(const FdTrafficStats *stats);
/**
 * 获取 RTT（Round Trip Time）
 * @param stats 指向 FdTrafficStats 结构体的指针
 * @return 成功返回 RTT 值（毫秒），失败返回 -1
 * @note 该函数仅用于获取最新的统计信息，不会重置计
 */
u_int32_t etos_stats_get_rtt(const FdTrafficStats *stats);
/**
 * 创建 TCP 连接（支持 IPv4/IPv6 自动解析）
 * @param host 目标主机 IP 或域名
 * @param port 目标端口
 * @param timeout_ms 连接超时（毫秒），<=0 表示阻塞
 * @return 成功返回 socket fd，失败返回 -1
 */
int etos_socket_connect(const char *host, int port, int timeout_ms);

/**
 * 通过代理创建连接
 * @param type 代理类型 (ETOS_PROXY_SOCKS5 / ETOS_PROXY_HTTP)
 * @param proxy_host 代理服务器地址
 * @param proxy_port 代理服务器端口
 * @param timeout_ms 全局超时（毫秒）
 * @param target_host 目标主机
 * @param target_port 目标端口
 * @param user 认证用户名（无认证传 NULL）
 * @param password 认证密码（无认证传 NULL）
 */
int etos_socket_connect_proxy(int type, const char *proxy_host, int proxy_port, int timeout_ms, const char *target_host, int target_port, const char *user, const char *password);

/** 带超时的 Send/Recv */
ssize_t etos_socket_send_timeout(int fd, const char *buf, size_t len, int flags, int timeout_ms);
ssize_t etos_socket_recv_timeout(int fd, char *buf, size_t len, int flags, int timeout_ms);

/** 原始数据收发 */
ssize_t etos_socket_send(int fd, const char *buf, size_t len, int flags);
ssize_t etos_socket_recv(int fd, char *buf, size_t len, int flags);

ssize_t libssh2_recv(int sock, void *buffer, size_t length, int flags);
ssize_t libssh2_send(int sock, const void *buffer, size_t length, int flags);

/** 关闭传输通道 (how: SHUT_RD=0, SHUT_WR=1, SHUT_RDWR=2) */
int etos_socket_shutdown(int fd, int how);

/** 设置阻塞或非阻塞模式 */
int etos_socket_set_blocking(int fd, bool blocking);

/** 关闭句柄并释放资源 */
void etos_socket_close(int fd);

/** 检查连接状态 */
bool etos_socket_is_connect(int fd);

/**
 * 设置 TCP KeepAlive 参数 (Apple 平台专用参数支持)
 * @param idle_sec 首次心跳前的空闲时间(秒)
 * @param interval_sec 心跳包发送间隔(秒)
 * @param count 没收到响应时的重试次数
 */
int etos_socket_set_keepalive(int fd, bool enable, int idle_sec, int interval_sec, int count);

/** 设置 TCP_NODELAY (禁用 Nagle 算法，降低延迟) */
int etos_socket_set_nodelay(int fd, bool enable);

/** 获取当前线程最后一次 errno */
int etos_socket_last_error(void);

/** 获取错误码描述 */
const char *etos_socket_strerror(int errnum);

/**
 * @brief 获取已连接套接字的远端 IP 和端口
 *
 * @param fd Socket 文件描述符
 * @param ip_buf 用于接收 IP 字符串的缓冲区 (建议长度 >= INET6_ADDRSTRLEN，即 46
 * 字节)
 * @param ip_buf_len 缓冲区长度
 * @param port 用于接收端口号的指针
 * @return int 成功返回 0，失败返回 -1
 */
int etos_socket_get_peer_info(int fd, char *ip_buf, size_t ip_buf_len, int *port);
/**
 * @brief 获取套接字的本地 (Client) IP 和端口
 *
 * @param fd Socket 文件描述符
 * @param ip_buf 用于接收 IP 字符串的缓冲区 (建议长度 >= INET6_ADDRSTRLEN，即 46
 * 字节)
 * @param ip_buf_len 缓冲区长度
 * @param port 用于接收端口号的指针
 * @return int 成功返回 0，失败返回 -1
 */
int etos_socket_get_local_info(int fd, char *ip_buf, size_t ip_buf_len, int *port);

#ifdef __cplusplus
}
#endif

#endif /* ETOS_SOCKET_H */
