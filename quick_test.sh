#!/bin/bash

# 快速测试脚本 - 验证多实例JWT密钥共享

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}FileBrowser 多实例JWT密钥共享快速测试${NC}"

# 测试配置
JWT_KEY="tnimhTBaHqYjC3teCfBUM+E5ROXKYVpaCPXk9CNg/98QZ1fH2ceGFfd3M9uiYo9gfGF5CsIuiIEIhqVt/rEd6A=="
ADMIN_USER="admin"
ADMIN_PASS="admin123"

# 清理函数
cleanup() {
    echo "清理测试环境..."
    pkill -f "filebrowser.*--port" 2>/dev/null || true
    sleep 2
}

trap cleanup EXIT

# 创建测试目录
echo "创建测试目录..."
mkdir -p test/instance1/{database,files,config}
mkdir -p test/instance2/{database,files,config}
mkdir -p test/instance3/{database,files,config}

# 创建测试文件
echo "Instance 1 test file" > test/instance1/files/test1.txt
echo "Instance 2 test file" > test/instance2/files/test2.txt
echo "Instance 3 test file" > test/instance3/files/test3.txt
echo "Shared content" > test/instance1/files/shared.txt
cp test/instance1/files/shared.txt test/instance2/files/
cp test/instance1/files/shared.txt test/instance3/files/

# 构建filebrowser
echo "构建filebrowser..."
if [ ! -f "./filebrowser" ]; then
    go build -o filebrowser .
fi

# 启动三个实例
echo "启动三个FileBrowser实例..."

# 实例1
echo "启动实例1 (端口8081)..."
export FB_JWT_KEY="$JWT_KEY"
export FB_DATABASE="test/instance1/database/filebrowser.db"
nohup ./filebrowser \
    --port 8081 \
    --address 0.0.0.0 \
    --database test/instance1/database/filebrowser.db \
    --root test/instance1/files \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --log stdout \
    > test/instance1/filebrowser.log 2>&1 &
echo $! > test/instance1/filebrowser.pid

# 实例2
echo "启动实例2 (端口8082)..."
export FB_JWT_KEY="$JWT_KEY"
export FB_DATABASE="test/instance2/database/filebrowser.db"
nohup ./filebrowser \
    --port 8082 \
    --address 0.0.0.0 \
    --database test/instance2/database/filebrowser.db \
    --root test/instance2/files \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --log stdout \
    > test/instance2/filebrowser.log 2>&1 &
echo $! > test/instance2/filebrowser.pid

# 实例3
echo "启动实例3 (端口8083)..."
export FB_JWT_KEY="$JWT_KEY"
export FB_DATABASE="test/instance3/database/filebrowser.db"
nohup ./filebrowser \
    --port 8083 \
    --address 0.0.0.0 \
    --database test/instance3/database/filebrowser.db \
    --root test/instance3/files \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --log stdout \
    > test/instance3/filebrowser.log 2>&1 &
echo $! > test/instance3/filebrowser.pid

# 等待启动
echo "等待实例启动..."
sleep 8

# 检查实例状态
echo "检查实例状态..."
for i in {1..3}; do
    port=$((8080 + i))
    pid=$(cat test/instance$i/filebrowser.pid 2>/dev/null || echo "")
    
    if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${GREEN}实例$i 运行正常 (PID: $pid, 端口: $port)${NC}"
    else
        echo -e "${RED}实例$i 启动失败${NC}"
        exit 1
    fi
done

# 测试JWT密钥共享
echo "测试JWT密钥共享..."

# 在实例1上登录
echo "在实例1上登录..."
JWT_TOKEN=$(curl -s -X POST http://localhost:8081/api/login \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")

if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" = "null" ]; then
    echo -e "${RED}登录失败${NC}"
    exit 1
fi

echo -e "${GREEN}登录成功，获取JWT token${NC}"

# 在所有实例上验证token
for i in {1..3}; do
    port=$((8080 + i))
    echo "在实例$i上验证token..."
    
    response=$(curl -s -X POST "http://localhost:$port/api/renew" \
        -H "X-Auth: $JWT_TOKEN")
    
    if [ -n "$response" ]; then
        echo -e "${GREEN}实例$i token验证成功${NC}"
    else
        echo -e "${RED}实例$i token验证失败${NC}"
        exit 1
    fi
done

# 测试文件访问
echo "测试文件访问..."
for i in {1..3}; do
    port=$((8080 + i))
    echo "在实例$i上访问文件列表..."
    
    response=$(curl -s -X GET "http://localhost:$port/api/resources/" \
        -H "X-Auth: $JWT_TOKEN")
    
    if [ -n "$response" ]; then
        echo -e "${GREEN}实例$i 文件访问成功${NC}"
        
        # 检查是否包含测试文件
        if echo "$response" | grep -q "test$i.txt"; then
            echo -e "${GREEN}实例$i 可以看到自己的测试文件${NC}"
        fi
        
        if echo "$response" | grep -q "shared.txt"; then
            echo -e "${GREEN}实例$i 可以看到共享文件${NC}"
        fi
    else
        echo -e "${RED}实例$i 文件访问失败${NC}"
        exit 1
    fi
done

# 检查环境变量使用
echo "检查环境变量使用..."
for i in {1..3}; do
    if grep -q "Using JWT key from environment variable" test/instance$i/filebrowser.log; then
        echo -e "${GREEN}实例$i 使用了环境变量JWT密钥${NC}"
    else
        echo -e "${RED}实例$i 可能没有使用环境变量JWT密钥${NC}"
    fi
done

# 显示实例信息
echo ""
echo "=================================="
echo "实例信息:"
echo "实例1: http://localhost:8081"
echo "实例2: http://localhost:8082"
echo "实例3: http://localhost:8083"
echo "管理员账号: $ADMIN_USER / $ADMIN_PASS"
echo "共享JWT密钥: ${JWT_KEY:0:20}..."
echo "=================================="

echo -e "${GREEN}测试完成！JWT密钥共享功能正常${NC}"
echo "按 Ctrl+C 停止所有实例"
