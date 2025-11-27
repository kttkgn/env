#!/bin/bash
# 严格模式（Linux环境增强）
set -eo pipefail

# 性能监控脚本（仅支持CentOS/Ubuntu）
# 使用示例：
# ./perf_monitor.sh --duration 60 --interval 5 --output perf.log

# 初始化参数
DURATION=30
INTERVAL=2
OUTPUT_FILE=""
INTERFACE=""
DISK_PARTITION="/"
DAEMON_MODE=false
START_TIME=$(date +%s)

# 颜色定义（Linux终端兼容）
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"
}
log_warn() {
    echo -e "${YELLOW}[WARN] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"
}
log_error() {
    echo -e "${RED}[ERROR] $(date +"%Y-%m-%d %H:%M:%S") $1${NC}"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                log_error "时长必须为正整数，当前值：$2"
            fi
            DURATION="$2"
            shift 2
            ;;
        --interval)
            if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                log_error "间隔必须为正整数，当前值：$2"
            fi
            INTERVAL="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
            if [ ! -d "$OUTPUT_DIR" ] && ! mkdir -p "$OUTPUT_DIR"; then
                log_error "输出目录创建失败：$OUTPUT_DIR"
            fi
            shift 2
            ;;
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --disk)
            DISK_PARTITION="$2"
            if ! df -h "$DISK_PARTITION" &>/dev/null; then
                log_error "磁盘分区不存在：$DISK_PARTITION"
            fi
            shift 2
            ;;
        --daemon)
            DAEMON_MODE=true
            shift
            ;;
        --help|-h)
            echo "用法：$0 [选项]"
            echo "选项："
            echo "  --duration <秒>      监控总时长（默认30）"
            echo "  --interval <秒>      采样间隔（默认2）"
            echo "  --output <文件>      输出日志文件路径"
            echo "  --interface <接口>   网络接口（如eth0，默认自动检测）"
            echo "  --disk <分区>        监控的磁盘分区（默认/）"
            echo "  --daemon             后台运行模式"
            echo "  --help/-h            显示帮助信息"
            exit 0
            ;;
        *)
            log_error "未知参数：$1（使用--help查看帮助）"
            ;;
    esac
done

# 后台运行处理
if $DAEMON_MODE; then
    log_info "后台运行模式启动，进程ID：$$"
    if [ -z "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="/tmp/perf_monitor_$(date +%Y%m%d_%H%M%S).log"
        log_info "后台模式默认输出文件：$OUTPUT_FILE"
    fi
    nohup "$0" --duration "$DURATION" --interval "$INTERVAL" \
        --output "$OUTPUT_FILE" --interface "$INTERFACE" --disk "$DISK_PARTITION" \
        >/dev/null 2>&1 &
    exit 0
fi

# 自动检测Linux默认网络接口
detect_default_interface() {
    if [ -n "$INTERFACE" ]; then
        if ! ip link show "$INTERFACE" &>/dev/null; then
            log_error "指定的网络接口不存在：$INTERFACE"
        fi
        return
    fi

    # Linux优先检测常用接口（适配CentOS/Ubuntu）
    local if_list=("eth0" "ens33" "ens160" "enp0s3" "wlan0" "bond0")
    for iface in "${if_list[@]}"; do
        if ip link show "$iface" &>/dev/null; then
            INTERFACE="$iface"
            return
        fi
    done

    # 兜底：检测默认路由对应的接口
    local default_if=$(ip route show default | awk '/default/ {print $5}')
    if [ -n "$default_if" ] && ip link show "$default_if" &>/dev/null; then
        INTERFACE="$default_if"
        return
    fi

    log_warn "未检测到有效网络接口，网络监控功能将禁用"
    INTERFACE=""
}

# 检查Linux依赖（CentOS/Ubuntu适配）
check_dependencies() {
    # 必选工具（Linux标配）
    local required_tools=("top" "df" "date" "sleep" "free" "ip" "bc")
    # 可选工具
    local optional_tools=("ifstat")

    # 检查必选工具
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            # 给出CentOS/Ubuntu安装提示
            if [[ "$tool" == "bc" ]]; then
                log_error "缺少必选工具：$tool（CentOS安装：yum install bc -y；Ubuntu安装：apt install bc -y）"
            else
                log_error "缺少必选工具：$tool，请安装后重试"
            fi
        fi
    done

    # 检查可选工具（ifstat）
    if ! command -v ifstat &>/dev/null; then
        log_warn "缺少ifstat，网络监控禁用（CentOS安装：yum install ifstat -y；Ubuntu安装：apt install ifstat -y）"
    fi
}

# 监控核心函数（仅Linux）
monitor() {
    local current_time=$(date +"%Y-%m-%d %H:%M:%S")

    # 1. CPU使用率（Linux原生逻辑，更准确）
    local cpu_usage
    # 排除idle计算总使用率，兼容不同top版本
    cpu_usage=$(top -bn1 | awk '/^%Cpu/ {idle=$8} END {print 100 - idle}' | cut -d. -f1)
    cpu_usage=${cpu_usage:-0}

    # 2. 内存使用率（Linux标准free命令）
    local mem_usage="0.0"
    local mem_total=$(free -b | awk '/Mem/ {print $2}')
    local mem_used=$(free -b | awk '/Mem/ {print $3}')
    # 避免除以0
    if [ "$mem_total" -gt 0 ]; then
        mem_usage=$(echo "scale=1; $mem_used / $mem_total * 100" | bc)
    fi
    mem_usage=${mem_usage:-0.0}

    # 3. 磁盘使用率（Linux df兼容）
    local disk_usage
    disk_usage=$(df -h "$DISK_PARTITION" | awk 'NR==2 {gsub("%",""); print $5}')
    disk_usage=${disk_usage:-0}

    # 4. 网络流量（Linux ifstat优化）
    local net_rx="0" net_tx="0"
    if [ -n "$INTERFACE" ] && command -v ifstat &>/dev/null; then
        # 强制使用Linux原生参数，避免兼容问题
        local ifstat_output=$(ifstat -i "$INTERFACE" -b -n -q 1 1 2>/dev/null)
        net_rx=$(echo "$ifstat_output" | awk 'NR==2 {print $1}' | cut -d. -f1)
        net_tx=$(echo "$ifstat_output" | awk 'NR==2 {print $2}' | cut -d. -f1)
        # 转换为KB/s（ifstat输出默认是byte/s）
        net_rx=$((net_rx / 1024))
        net_tx=$((net_tx / 1024))
    fi

    # 格式化输出
    local output
    output=$(printf "[%s] CPU: %3s%% | 内存: %5s%% | 磁盘(%s): %3s%% | 网络(%s)接收: %5sKB/s | 发送: %5sKB/s" \
        "$current_time" "$cpu_usage" "$mem_usage" "$DISK_PARTITION" "$disk_usage" \
        "$INTERFACE" "$net_rx" "$net_tx")

    echo -e "${GREEN}$output${NC}"
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$output" >> "$OUTPUT_FILE"
    fi
}

# 初始化
check_dependencies
detect_default_interface

# 输出配置信息
log_info "===== 性能监控配置 ====="
log_info "系统类型：$(uname -s) $(uname -r)（$(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')）"
log_info "监控时长：${DURATION}秒"
log_info "采样间隔：${INTERVAL}秒"
log_info "磁盘分区：${DISK_PARTITION}"
log_info "网络接口：${INTERFACE:-禁用}"
if [ -n "$OUTPUT_FILE" ]; then
    log_info "输出文件：${OUTPUT_FILE}"
fi
log_info "========================"

# 核心监控循环（Linux优化）
while true; do
    monitor || log_warn "本次采样出现异常，继续下一次"

    current_timestamp=$(date +%s)
    elapsed=$((current_timestamp - START_TIME))

    if [ "$elapsed" -ge "$DURATION" ]; then
        break
    fi

    # 精准休眠（补偿采样耗时）
    now_timestamp=$(date +%s)
    sample_cost=$((now_timestamp - current_timestamp))
    remaining_sleep=$((INTERVAL - sample_cost))

    if [ "$remaining_sleep" -gt 0 ]; then
        sleep "$remaining_sleep"
    fi
done

log_info "===== 性能监控结束 ====="
if [ -n "$OUTPUT_FILE" ]; then
    log_info "监控日志已保存至：${OUTPUT_FILE}"
fi
