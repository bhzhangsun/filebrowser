#!/bin/bash

# FileBrowser 多实例启动脚本
# 启动三个实例，使用环境变量共享JWT密钥

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置
JWT_KEY="tnimhTBaHqYjC3teCfBUM+E5ROXKYVpaCPXk9CNg/98QZ1fH2ceGFfd3M9uiYo9gfGF5CsIuiIEIhqVt/rEd6A=="
ADMIN_USER="admin"
ADMIN_PASS="admin123"

# 实例配置
INSTANCES=(
    "instance1:8081:test/instance1"
    "instance2:8082:test/instance2"
    "instance3:8083:test/instance3"
)

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 清理函数
cleanup() {
    log_info "清理环境..."
    pkill -f "filebrowser.*--port" 2>/dev/null || true
    sleep 2
}

# 设置退出时清理
trap cleanup EXIT

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v filebrowser &> /dev/null; then
        if [ ! -f "./filebrowser" ]; then
            log_info "构建filebrowser..."
            go build -o filebrowser .
        fi
        export PATH="$PWD:$PATH"
    fi
    
    log_success "依赖检查完成"
}

# 准备测试环境
prepare_test_environment() {
    log_info "准备测试环境..."
    
    # 创建test目录
    mkdir -p test
    
    # 为每个实例创建目录
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        # 创建实例目录
        mkdir -p "$dir/database" "$dir/files" "$dir/config"
        
        # 创建测试文件
        echo "Instance $name test file - $(date)" > "$dir/files/test_$name.txt"
        echo "Shared content for all instances" > "$dir/files/shared.txt"
        
        log_info "创建实例 $name 目录: $dir"
    done
    
    log_success "测试环境准备完成"
}

# 启动实例
start_instances() {
    log_info "启动FileBrowser实例..."
    
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        log_info "启动实例 $name (端口: $port, 目录: $dir)"
        
        # 设置环境变量
        export FB_JWT_KEY="$JWT_KEY"
        export FB_DATABASE="$dir/database/filebrowser.db"
        
        # 启动实例
        nohup filebrowser \
            --port "$port" \
            --address "127.0.0.1" \
            --database "$dir/database/filebrowser.db" \
            --root "$dir/files" \
            --username "$ADMIN_USER" \
            --password "$ADMIN_PASS" \
            --log "stdout" \
            > "$dir/filebrowser.log" 2>&1 &
        
        # 保存进程ID
        echo $! > "$dir/filebrowser.pid"
        
        log_success "实例 $name 启动完成 (PID: $(cat $dir/filebrowser.pid))"
    done
    
    # 等待实例启动
    log_info "等待实例启动..."
    sleep 5
}

# 检查实例状态
check_instances() {
    log_info "检查实例状态..."
    
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        # 检查进程
        if [ -f "$dir/filebrowser.pid" ]; then
            pid=$(cat "$dir/filebrowser.pid")
            if ps -p "$pid" > /dev/null 2>&1; then
                log_success "实例 $name 进程运行正常 (PID: $pid)"
            else
                log_error "实例 $name 进程未运行"
                return 1
            fi
        else
            log_error "实例 $name PID文件不存在"
            return 1
        fi
        
        # 检查端口
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            log_success "实例 $name 端口 $port 监听正常"
        else
            log_warning "实例 $name 端口 $port 可能未监听"
        fi
    done
}

# 测试JWT密钥共享
test_jwt_sharing() {
    log_info "测试JWT密钥共享..."
    
    # 在实例1上登录获取token
    log_info "在实例1上登录..."
    JWT_TOKEN=$(curl -s -X POST http://localhost:8081/api/login \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")
    
    if [ -z "$JWT_TOKEN" ] || [ "$JWT_TOKEN" = "null" ]; then
        log_error "实例1登录失败"
        return 1
    fi
    
    log_success "获取JWT token: ${JWT_TOKEN:0:20}..."
    
    # 在所有实例上验证token
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        log_info "在实例 $name 上验证token..."
        response=$(curl -s -X POST "http://localhost:$port/api/renew" \
            -H "X-Auth: $JWT_TOKEN")
        
        if [ -n "$response" ]; then
            log_success "实例 $name token验证成功"
        else
            log_error "实例 $name token验证失败"
            return 1
        fi
    done
    
    log_success "JWT密钥共享测试通过"
}

# 测试文件访问
test_file_access() {
    log_info "测试文件访问..."
    
    # 获取token
    JWT_TOKEN=$(curl -s -X POST http://localhost:8081/api/login \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}")
    
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        log_info "在实例 $name 上访问文件列表..."
        response=$(curl -s -X GET "http://localhost:$port/api/resources/" \
            -H "X-Auth: $JWT_TOKEN")
        
        if [ -n "$response" ]; then
            log_success "实例 $name 文件访问成功"
            
            # 检查是否包含测试文件
            if echo "$response" | grep -q "test_$name.txt"; then
                log_success "实例 $name 可以看到自己的测试文件"
            fi
            
            if echo "$response" | grep -q "shared.txt"; then
                log_success "实例 $name 可以看到共享文件"
            fi
        else
            log_error "实例 $name 文件访问失败"
            return 1
        fi
    done
}

# 显示实例信息
show_instance_info() {
    log_info "实例信息:"
    echo "=================================="
    
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        echo "实例: $name"
        echo "  端口: $port"
        echo "  目录: $dir"
        echo "  URL: http://localhost:$port"
        echo "  日志: $dir/filebrowser.log"
        echo "  PID: $(cat $dir/filebrowser.pid 2>/dev/null || echo 'N/A')"
        echo "---"
    done
    
    echo "共享JWT密钥: ${JWT_KEY:0:20}..."
    echo "管理员账号: $ADMIN_USER / $ADMIN_PASS"
    echo "=================================="
}

# 停止实例
stop_instances() {
    log_info "停止所有实例..."
    
    for instance_config in "${INSTANCES[@]}"; do
        IFS=':' read -r name port dir <<< "$instance_config"
        
        if [ -f "$dir/filebrowser.pid" ]; then
            pid=$(cat "$dir/filebrowser.pid")
            if ps -p "$pid" > /dev/null 2>&1; then
                kill "$pid"
                log_success "停止实例 $name (PID: $pid)"
            fi
        fi
    done
    
    sleep 2
}

# 主函数
main() {
    case "${1:-start}" in
        "start")
            log_info "启动FileBrowser多实例测试环境..."
            
            check_dependencies
            prepare_test_environment
            start_instances
            check_instances
            test_jwt_sharing
            test_file_access
            show_instance_info
            
            log_success "所有实例启动完成！"
            log_info "按 Ctrl+C 停止所有实例"
            
            # 保持脚本运行
            while true; do
                sleep 10
                # 检查实例状态
                for instance_config in "${INSTANCES[@]}"; do
                    IFS=':' read -r name port dir <<< "$instance_config"
                    if [ -f "$dir/filebrowser.pid" ]; then
                        pid=$(cat "$dir/filebrowser.pid")
                        if ! ps -p "$pid" > /dev/null 2>&1; then
                            log_error "实例 $name 已停止"
                        fi
                    fi
                done
            done
            ;;
        "stop")
            stop_instances
            log_success "所有实例已停止"
            ;;
        "status")
            check_instances
            show_instance_info
            ;;
        "test")
            test_jwt_sharing
            test_file_access
            ;;
        "clean")
            log_info "清理测试环境..."
            stop_instances
            rm -rf test
            log_success "测试环境已清理"
            ;;
        *)
            echo "用法: $0 {start|stop|status|test|clean}"
            echo "  start  - 启动所有实例"
            echo "  stop   - 停止所有实例"
            echo "  status - 显示实例状态"
            echo "  test   - 运行测试"
            echo "  clean  - 清理测试环境"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
