#!/bin/bash
set -euo pipefail

CFG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak.$(date +%F_%H%M%S)"

# 1) 检测防火墙（按你原逻辑：firewalld 开就退出）
if systemctl is-active --quiet firewalld.service; then
  echo "防火墙（firewalld）已开启，请手动放行新端口号后再执行。"
  exit 1
fi

# 2) 读取当前“生效端口”（最准确）
old_ports="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | xargs || true)"
if [[ -z "${old_ports}" ]]; then
  old_ports="22"  # 极端情况兜底
fi

# 3) 读入新端口
read -r -p "请输入新的SSH端口号：" new_port

# 基本校验
if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
  echo "端口号不合法：$new_port"
  exit 1
fi

# 4) 备份配置
cp -a "$CFG" "$BACKUP"

# 5) 修改配置：
#    - 删除所有 Port 行（包括注释的 #Port、以及多个 Port）
#    - 在文件顶部写入新的 Port（确保生效且易读）
#    说明：不尝试“替换某个固定值”，而是统一重写 Port 配置
tmp="$(mktemp)"
{
  echo "Port $new_port"
  echo
  grep -v -E '^\s*#?\s*Port\s+' "$CFG"
} > "$tmp"
cat "$tmp" > "$CFG"
rm -f "$tmp"

# 6) 配置校验（非常重要）
if ! sshd -t; then
  echo "sshd 配置校验失败，正在回滚：$BACKUP"
  cp -a "$BACKUP" "$CFG"
  exit 1
fi

# 7) 重启服务（Debian 12 通常是 ssh.service）
if systemctl list-unit-files | grep -q '^ssh\.service'; then
  systemctl restart ssh.service
elif systemctl list-unit-files | grep -q '^sshd\.service'; then
  systemctl restart sshd.service
else
  # 兜底
  systemctl restart ssh || true
  systemctl restart sshd || true
fi

# 8) 输出结果（不要硬写 22 失效）
echo "SSH 端口已从：${old_ports}  修改为：${new_port}"
echo "请使用新端口登录：ssh -p ${new_port} <user>@<host>"
echo "如无法登录，请检查防火墙是否放行 TCP/${new_port}"
