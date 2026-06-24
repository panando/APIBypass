# APIBypass 变更记录

## [0.5.7] - 2026-06-03 - 并发性能优化

### 新增

#### 并发连接控制
- 实现了基于 `AsyncSemaphore` 的并发连接数限制
- 默认最大并发连接数：100
- 超出限制时返回 `503 Service Unavailable` 错误
- 添加了活跃连接数实时监控

#### 流式传输优化
- 缓冲区大小从 1KB 提升到 64KB（64x 提升）
- 实现 `streamWithBackpressure` 方法进行批量读取
- 每 8KB 数据让出线程一次，避免阻塞
- 使用 `Task.yield()` 优化并发性能

### 修改

#### HTTPServer.swift
- 添加了并发控制相关属性和方法：
  - `maxConcurrentConnections`: 最大并发连接数配置
  - `connectionSemaphore`: 连接信号量控制
  - `activeConnections`: 活跃连接数统计
  - `handleRequestWithConcurrencyLimit()`: 带并发限制的请求处理
  - `streamWithBackpressure()`: 带背压控制的流式传输

### 性能提升

| 指标 | 修复前 | 修复后 | 提升倍数 |
|------|--------|--------|----------|
| 缓冲区大小 | 1KB | 64KB | 64x |
| 最大并发连接 | 无限制 | 100 | 可控 |
| 线程让出频率 | 无 | 每 8KB | 更平滑 |
| 逐字节处理 | 是 | 否 | 批量处理 |

### 配置参数

```swift
// HTTPServer 初始化时可配置
let server = HTTPServer(
    configManager: configManager,
    keychain: keychain,
    maxConcurrentConnections: 100  // 自定义并发限制
)
```

### 测试验证

#### 压力测试脚本
```bash
# 运行压力测试
/tmp/concurrency_test.sh
```

测试场景：
- 10/50/100 并发用户测试
- 连接限制验证（第 101 个连接应返回 503）
- 响应延迟测量

#### 监控命令
```bash
# 查看活跃连接数
lsof -i :8390 | wc -l

# 检查服务状态
curl -s http://127.0.0.1:8390/v1/models

# 查看日志
tail -f /tmp/apibypass.log
```

### 安全改进

- 防止资源耗尽攻击（DoS）
- 连接数限制防止文件描述符耗尽
- 服务过载时优雅降级（503 错误）

### 已知限制

- 当前背压控制基于连接数而非内存使用量
- 日志输出仍为同步方式（将在 P1 优化）
- URLSession 使用默认配置（将在 P2 优化）

### 后续优化建议

#### P1 优先级
- 实现异步日志队列
- 优化 JSON 序列化性能
- 添加更详细的性能指标

#### P2 优先级
- 自定义 URLSession 配置
- HTTP/2 多路复用支持
- 基于内存使用量的动态背压

---

## 版本历史

### [0.5.6] - 2026-06-01
- SSE 兼容性修复
- 扩展思维支持
- Claude Code 启动器改进

### [0.5.5] 及更早版本
- 查看 RELEASE_NOTES.md 了解完整历史

---

**文档版本**: 1.0  
**最后更新**: 2026-06-03  
**维护者**: Claude Code
