#!/bin/bash
# LB2004 快速分析脚本 —— 找 .config 和 model_database.conf 的目录
# 删除多余的 patch，分析哪个设备树文件可用做模板，看融合了 BSP 和 IPC 支持
#
# 用法：
#   bash lb2004-analyze.sh
#   bash lb2004-analyze.sh --kernel-dir /path/to/kernel
#   bash lb2004-analyze.sh --verbose

set -euo pipefail

VERBOSE=false
KERNEL_DIR="$(dirname "$0")/kernel-patch/beta/linux-6.1.y-rockchip-main"
SUMMARY_FILE="lb2004-analysis-summary.md"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-dir) KERNEL_DIR="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

[[ -d "$KERNEL_DIR" ]] || { echo "ERROR: Directory '$KERNEL_DIR' not found"; exit 1; }

echo "# LB2004 设备树分析报告"
echo "================================================"
echo "时间: $(date)"
echo "目录: $(realpath "$KERNEL_DIR")"
echo

# ── 1. 发现资源 ──
echo "## 1. 本地资源清单"
echo "--------------------------------"
if $VERBOSE; then
    ls -lAR "$KERNEL_DIR"
else
    ls -1 "$KERNEL_DIR"
fi
echo

# ── 2. 找出有 .config 和 model_database.conf 的目录 ──
echo "## 2. 设备树资源发现"
echo ""
echo "**搜索 .config 文件:**"
find / -name ".config" -type f 2>/dev/null | while read f; do
    echo "- $f"
done

echo ""
echo "**搜索 model_database.conf 文件:**"
find / -name "model_database.conf" -type f 2>/dev/null | while read f; do
    echo "- $f"
done

echo ""
echo "**搜索 Rockchip .config 文件:**"
find / -path "*/rockchip*/.config" -type f 2>/dev/null | while read f; do
    echo "- $f"
done

echo ""

# ── 3. BSP 的 Makefile 中搜索 target 设备树 ──
echo "## 3. BSP 设备树模板匹配"
MATCH_FILE="$KERNEL_DIR/rk3566-lb2004-bsp6.1.dts"

# 从 DTS 中提取所需的核心外设
echo ""
echo "从 LB2004 DTS 提取关键外设节点:"
BSP_NODES=""
for node in "rknpu" "npu" "bus_npu" "can0" "can1" "can2" "pcie30phy" "hdmi_in" "hdmi_out" "usb_host1_xhci" "usb2phy1_host" "usb2phy1_otg"; do
    if grep -q "&$node" "$MATCH_FILE" 2>/dev/null; then
        echo "  ✅ 包含: &$node"
        BSP_NODES="$BSP_NODES $node"
    else
        echo "  ❌ 缺少: &$node"
    fi
done

echo ""

# ── 4. 从 idbloader/u-boot 方面 ──
echo "## 4. 引导加载程序审核"
echo ""
echo "需要从 main 分支的 md1000 路径复制:"
echo "  - idbloader.img"
echo "  - u-boot.itb"

# 检查 remote main 分支是否存在这些文件
if git rev-parse origin/main >/dev/null 2>&1; then
    echo ""
    echo "在 main 分支中找到的 bootloader 相关文件:"
    git ls-tree -r origin/main --name-only | grep -E "idbloader|u-boot|\\.itb|\\.img" | while read f; do
        echo "  origin/main:$f"
    done
fi

echo ""

# ── 5. 清理 patch 文件 ──
echo "## 5. 冗余 patch 清理"
echo ""
echo "待删除的 patch 文件:"
find "$KERNEL_DIR" -name "*.patch" -type f | while read f; do
    echo "  - DELETE: $f"
done

read -p "删除以上所有 patch 文件? [y/N] " DEL_CONFIRM
if [[ "$DEL_CONFIRM" == "y" || "$DEL_CONFIRM" == "Y" ]]; then
    find "$KERNEL_DIR" -name "*.patch" -type f -delete
    echo "已删除所有 patch 文件"
else
    echo "跳过删除"
fi

echo ""
echo "## 6. 后续步骤"
echo ""
echo "1. 从 main 分支的 md1000 路径提取 idbloader.img 和 u-boot.itb"
echo "2. 如果有可用的 .config 文件，在 Docker 注入容器内核源时嵌入"
echo "3. device tree 合并到 BSP 内核 Makefile（添加条目）"
echo "4. 单独编译 DTS 生成 .dtb"

echo ""
echo "================================================"
echo "分析完成"