#!/bin/bash

# 切换到脚本所在目录（防止不同 cwd 启动时 data.sqlite3 / 日志路径漂移）
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# 停止已有进程（含旧 watchdog，避免重复监控）
# app 用 SIGTERM 让其走 graceful shutdown（保住 sqlite WAL / 日志缓冲 / 在飞请求）
# watchdog 用 SIGKILL 直接干掉，bash sleeper 没什么需要清理的
pkill -f claude-api-linux 2>/dev/null
pkill -9 -f claude-api-watchdog 2>/dev/null

# 等旧 app 真正退出（main.go 优雅关闭最多 30s），最多等 35s
# 不等的话 sleep 1 后旧实例可能还在占端口，新实例启动失败
for i in $(seq 1 35); do
    pgrep -f claude-api-linux > /dev/null 2>&1 || break
    sleep 1
done

# 兜底：35s 还没退出说明 graceful shutdown 卡死了，强杀避免新实例端口冲突
if pgrep -f claude-api-linux > /dev/null 2>&1; then
    pkill -9 -f claude-api-linux 2>/dev/null
    sleep 1
fi

chmod +x claude-api-linux

# Go runtime 调优（4GB 内存）
export GOMEMLIMIT=3000MiB   # 软内存上限，留 1GB 给 OS/sqlite/非 Go 内存；挡住突发尖峰的尾部 OOM 风险
export GOMAXPROCS=2         # 显式锁定核心数（cgroup 受限环境下默认值会读错；如果是 4 核请改成 4）
# GOGC 不设，用默认 100：内存宽松，没必要拿 CPU 换内存

# 启动主进程
nohup ./claude-api-linux > /dev/null 2>&1 &
echo "claude api started, pid: $!"

# 启动 watchdog：10s 检查一次，进程不在了就重新执行本脚本
# 通过 ps 看到的命令行里包含 "claude-api-watchdog" 这个 tag，便于下次启动时 pkill 干掉
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
nohup bash -c "
    # claude-api-watchdog
    cd '$SCRIPT_DIR'
    while true; do
        sleep 10
        if ! pgrep -f claude-api-linux > /dev/null 2>&1; then
            echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] claude-api-linux 已停止，重新执行 claude_start.sh\" >> claude-watchdog.log
            exec bash '$SCRIPT_PATH'
        fi
    done
" > /dev/null 2>&1 &
echo "watchdog started, pid: $!"
