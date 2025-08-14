# JWT密钥环境变量配置指南

## 概述

FileBrowser现在支持通过环境变量`FB_JWT_KEY`来配置JWT签名密钥，但仅在特定阶段使用。这个设计确保了密钥管理的一致性和安全性。

## 功能特性

- **初始化阶段优先**：在setup/init阶段优先使用`FB_JWT_KEY`环境变量
- **导入阶段智能处理**：在import阶段优先使用导入数据，如果为空则使用环境变量
- **运行时稳定性**：运行时从数据库settings中获取密钥，确保一致性
- **向后兼容**：不影响现有的随机密钥生成机制

## JWT密钥使用逻辑

### 1. 初始化阶段（setup/init）
**优先级**：环境变量 `FB_JWT_KEY` > 生成新密钥

- 在`filebrowser config init`命令中
- 在`filebrowser --username admin --password admin`快速设置中
- 如果设置了`FB_JWT_KEY`环境变量，使用该密钥
- 如果未设置环境变量，生成新的随机密钥

### 2. 导入阶段（import）
**优先级**：导入的密钥 > 环境变量 `FB_JWT_KEY` > 生成新密钥

- 在`filebrowser config import`命令中
- 如果导入的配置包含有效的JWT密钥，使用导入的密钥
- 如果导入的密钥为空或无效，检查环境变量
- 如果环境变量也未设置，生成新的随机密钥

### 3. 运行时阶段
**来源**：数据库settings中存储的密钥

- JWT签名验证时从settings.Key获取密钥
- JWT token生成时从settings.Key获取密钥
- 不再检查环境变量，确保运行时稳定性

## 实现细节

### 核心函数

```go
// GetOrGenerateKey 统一的JWT密钥获取函数
// 优先级：环境变量 > 生成新密钥
func GetOrGenerateKey() ([]byte, error)
```

### 使用场景

1. **初始化**：`generateKey()` -> `GetOrGenerateKey()`
2. **导入**：`generateKey()` -> `GetOrGenerateKey()`
3. **运行时**：直接使用`settings.Key`

## 使用方法

### 1. Docker部署

#### 单实例部署
```yaml
# docker-compose.yml
version: '3.8'
services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    ports:
      - "8080:80"
    volumes:
      - ./database:/database
      - ./files:/srv
      - ./config:/config
    environment:
      - FB_JWT_KEY=your-secret-jwt-key-here
      - FB_DATABASE=/database/filebrowser.db
    restart: unless-stopped
```

#### 多实例部署（共享JWT密钥）
```yaml
# docker-compose.yml
version: '3.8'
services:
  filebrowser-1:
    image: filebrowser/filebrowser:latest
    ports:
      - "8081:80"
    volumes:
      - ./database:/database
      - ./files:/srv
      - ./config:/config
    environment:
      - FB_JWT_KEY=shared-jwt-secret-key-for-all-instances
      - FB_DATABASE=/database/filebrowser.db
    restart: unless-stopped

  filebrowser-2:
    image: filebrowser/filebrowser:latest
    ports:
      - "8082:80"
    volumes:
      - ./database:/database
      - ./files:/srv
      - ./config:/config
    environment:
      - FB_JWT_KEY=shared-jwt-secret-key-for-all-instances
      - FB_DATABASE=/database/filebrowser.db
    restart: unless-stopped
```

### 2. 命令行部署

#### 设置环境变量
```bash
# Linux/macOS
export FB_JWT_KEY="your-secret-jwt-key-here"

# Windows
set FB_JWT_KEY=your-secret-jwt-key-here
```

#### 初始化数据库
```bash
# 使用环境变量中的JWT密钥初始化
filebrowser config init

# 或者使用快速设置
filebrowser --username admin --password admin
```

#### 导入配置
```bash
# 导入配置时会优先使用导入的密钥
filebrowser config import config.json

# 如果导入的密钥为空，会使用环境变量或生成新密钥
```

### 3. Kubernetes部署

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: filebrowser
spec:
  replicas: 3
  selector:
    matchLabels:
      app: filebrowser
  template:
    metadata:
      labels:
        app: filebrowser
    spec:
      containers:
      - name: filebrowser
        image: filebrowser/filebrowser:latest
        ports:
        - containerPort: 80
        env:
        - name: FB_JWT_KEY
          valueFrom:
            secretKeyRef:
              name: filebrowser-secrets
              key: jwt-key
        - name: FB_DATABASE
          value: "/database/filebrowser.db"
        volumeMounts:
        - name: database
          mountPath: /database
        - name: files
          mountPath: /srv
      volumes:
      - name: database
        persistentVolumeClaim:
          claimName: filebrowser-db-pvc
      - name: files
        persistentVolumeClaim:
          claimName: filebrowser-files-pvc
```

```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: filebrowser-secrets
type: Opaque
data:
  jwt-key: <base64-encoded-jwt-key>
```

## 密钥要求

### 密钥长度
- **推荐长度**：至少32字节（256位）
- **最小长度**：16字节（128位）
- **最大长度**：无限制，但建议不超过512字节

### 密钥格式
- **字符串格式**：直接使用字符串作为密钥
- **Base64格式**：支持Base64编码的密钥
- **十六进制格式**：支持十六进制编码的密钥

### 示例密钥
```bash
# 简单字符串密钥
FB_JWT_KEY="my-super-secret-jwt-key-2024"

# Base64编码密钥
FB_JWT_KEY="bXktc3VwZXItc2VjcmV0LWp3dC1rZXktMjAyNA=="

# 十六进制密钥
FB_JWT_KEY="6d792d73757065722d7365637265742d6a77742d6b65792d32303234"
```

## 安全最佳实践

### 1. 密钥生成
```bash
# 生成强随机密钥
openssl rand -base64 64

# 或者使用Python
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

### 2. 密钥管理
- **环境变量**：在生产环境中使用环境变量或密钥管理服务
- **密钥轮换**：定期更换JWT密钥
- **访问控制**：限制对JWT密钥的访问权限

### 3. 监控和日志
```bash
# 查看日志确认密钥来源
docker logs filebrowser | grep "JWT key"

# 预期输出：
# Using JWT key from environment variable FB_JWT_KEY for initialization
# 或
# No JWT key found for initialization, generating new key
# 或
# Using JWT key from import
```

## 验证配置

### 1. 检查密钥来源
启动FileBrowser后，查看日志确认密钥来源：
```bash
docker logs filebrowser
```

### 2. 测试多实例认证
```bash
# 在实例1上登录
curl -X POST http://localhost:8081/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'

# 使用返回的JWT在实例2上访问
curl -H "X-Auth: <jwt-token>" http://localhost:8082/api/renew
```

### 3. 验证密钥一致性
```bash
# 检查数据库中的密钥
docker run --rm \
  -v $(pwd)/database:/database \
  filebrowser/filebrowser:latest \
  filebrowser config cat | grep -A 5 -B 5 "key"
```

## 故障排除

### 1. 环境变量未生效
- 检查环境变量名称是否正确：`FB_JWT_KEY`
- 确认环境变量已正确设置：`echo $FB_JWT_KEY`
- 重启容器以应用新的环境变量

### 2. 密钥长度问题
- 确保密钥长度至少为16字节
- 检查密钥是否包含特殊字符，可能需要转义

### 3. 多实例认证失败
- 确认所有实例使用相同的`FB_JWT_KEY`
- 检查网络连接和负载均衡器配置
- 验证JWT token格式是否正确

## 迁移指南

### 从随机密钥迁移到环境变量密钥

1. **备份当前数据库**
```bash
cp filebrowser.db filebrowser.db.backup
```

2. **设置环境变量**
```bash
export FB_JWT_KEY="your-new-shared-key"
```

3. **重新初始化数据库**
```bash
# 删除现有数据库
rm filebrowser.db

# 使用环境变量重新初始化
filebrowser config init
```

4. **验证迁移**
```bash
# 检查日志确认使用环境变量密钥
docker logs filebrowser | grep "JWT key"
```

## 总结

通过使用`FB_JWT_KEY`环境变量，您可以：

1. **简化部署**：在初始化阶段使用环境变量密钥
2. **提高安全性**：使用强密钥和密钥管理服务
3. **支持扩展**：轻松部署多个实例
4. **便于管理**：统一管理所有实例的JWT密钥
5. **确保稳定性**：运行时从数据库获取密钥，避免环境变量变化影响

这个功能使得FileBrowser更适合在生产环境中进行无状态部署和水平扩展，同时保持了运行时的一致性和稳定性。
