# FileBrowser 多实例JWT密钥共享测试

## 概述

本测试验证FileBrowser多实例部署中JWT密钥共享功能，确保多个实例可以使用相同的JWT密钥进行无状态认证。

## 测试脚本

### 1. 完整测试脚本 (`start_multi_instances.sh`)

功能完整的测试脚本，支持多种操作模式：

```bash
# 启动所有实例并运行测试
./start_multi_instances.sh start

# 停止所有实例
./start_multi_instances.sh stop

# 查看实例状态
./start_multi_instances.sh status

# 运行测试
./start_multi_instances.sh test

# 清理测试环境
./start_multi_instances.sh clean
```

### 2. 快速测试脚本 (`quick_test.sh`)

简化的测试脚本，快速验证功能：

```bash
./quick_test.sh
```

## 测试环境

### 实例配置

| 实例 | 端口 | 目录 | URL |
|------|------|------|-----|
| instance1 | 8081 | test/instance1 | http://localhost:8081 |
| instance2 | 8082 | test/instance2 | http://localhost:8082 |
| instance3 | 8083 | test/instance3 | http://localhost:8083 |

### 共享配置

- **JWT密钥**: `tnimhTBaHqYjC3teCfBUM+E5ROXKYVpaCPXk9CNg/98QZ1fH2ceGFfd3M9uiYo9gfGF5CsIuiIEIhqVt/rEd6A==`
- **管理员账号**: `admin` / `admin123`
- **环境变量**: `FB_JWT_KEY`

### 目录结构

```
test/
├── instance1/
│   ├── database/
│   ├── files/
│   │   ├── test1.txt
│   │   └── shared.txt
│   ├── config/
│   ├── filebrowser.log
│   └── filebrowser.pid
├── instance2/
│   ├── database/
│   ├── files/
│   │   ├── test2.txt
│   │   └── shared.txt
│   ├── config/
│   ├── filebrowser.log
│   └── filebrowser.pid
└── instance3/
    ├── database/
    ├── files/
    │   ├── test3.txt
    │   └── shared.txt
    ├── config/
    ├── filebrowser.log
    └── filebrowser.pid
```

## 测试内容

### 1. JWT密钥共享测试

- 在实例1上登录获取JWT token
- 在所有三个实例上验证相同的token
- 验证token在所有实例上都有效

### 2. 文件访问测试

- 验证每个实例可以访问自己的文件
- 验证共享文件在所有实例上都可见
- 测试文件列表API

### 3. 环境变量验证

- 检查日志确认使用了环境变量JWT密钥
- 验证`FB_JWT_KEY`环境变量正确生效

### 4. 实例状态监控

- 检查进程状态
- 检查端口监听
- 监控实例健康状态

## 运行测试

### 快速开始

```bash
# 1. 确保在filebrowser项目根目录
cd /path/to/filebrowser

# 2. 运行快速测试
./quick_test.sh
```

### 完整测试

```bash
# 1. 启动所有实例
./start_multi_instances.sh start

# 2. 查看状态
./start_multi_instances.sh status

# 3. 运行测试
./start_multi_instances.sh test

# 4. 停止实例
./start_multi_instances.sh stop

# 5. 清理环境
./start_multi_instances.sh clean
```

## 手动测试

### 1. 登录获取Token

```bash
# 在实例1上登录
curl -X POST http://localhost:8081/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

### 2. 验证Token

```bash
# 使用获取的token在所有实例上验证
JWT_TOKEN="your-jwt-token-here"

# 实例1
curl -X POST http://localhost:8081/api/renew \
  -H "X-Auth: $JWT_TOKEN"

# 实例2
curl -X POST http://localhost:8082/api/renew \
  -H "X-Auth: $JWT_TOKEN"

# 实例3
curl -X POST http://localhost:8083/api/renew \
  -H "X-Auth: $JWT_TOKEN"
```

### 3. 访问文件

```bash
# 获取文件列表
curl -X GET http://localhost:8081/api/resources/ \
  -H "X-Auth: $JWT_TOKEN"
```

## 预期结果

### 成功指标

1. **JWT密钥共享**: 所有实例都能验证相同的JWT token
2. **环境变量使用**: 日志显示使用了环境变量JWT密钥
3. **文件访问**: 每个实例都能正常访问文件
4. **实例状态**: 所有实例正常运行，端口正常监听

### 日志验证

检查每个实例的日志文件，应该看到：

```
Using JWT key from environment variable FB_JWT_KEY
```

### 测试验证

- ✅ 实例1登录成功
- ✅ 实例1 token验证成功
- ✅ 实例2 token验证成功
- ✅ 实例3 token验证成功
- ✅ 所有实例文件访问成功
- ✅ 环境变量JWT密钥使用确认

## 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   # 检查端口占用
   netstat -tlnp | grep :808
   ```

2. **权限问题**
   ```bash
   # 确保脚本有执行权限
   chmod +x *.sh
   ```

3. **依赖问题**
   ```bash
   # 确保filebrowser已构建
   go build -o filebrowser .
   ```

4. **环境变量问题**
   ```bash
   # 检查环境变量
   echo $FB_JWT_KEY
   ```

### 清理环境

```bash
# 停止所有实例
pkill -f "filebrowser.*--port"

# 清理测试目录
rm -rf test/

# 清理进程
ps aux | grep filebrowser
```

## 扩展测试

### 负载均衡测试

可以使用Nginx等负载均衡器进行进一步测试：

```nginx
upstream filebrowser {
    server localhost:8081;
    server localhost:8082;
    server localhost:8083;
}

server {
    listen 80;
    location / {
        proxy_pass http://filebrowser;
    }
}
```

### 压力测试

```bash
# 使用ab进行压力测试
ab -n 1000 -c 10 http://localhost:8081/
```

## 总结

通过这个测试，您可以验证：

1. **JWT密钥共享功能正常**
2. **多实例可以共享相同的JWT token**
3. **环境变量FB_JWT_KEY正确生效**
4. **无状态部署支持**
5. **水平扩展能力**

这个测试为生产环境的多实例部署提供了验证基础。
