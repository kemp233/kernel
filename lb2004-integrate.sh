#!/bin/bash
# LB2004 设备树 + 引导加载程序一键整合脚本
# 功能：
#   1. 从 kemp233/amlogic-s9xxx-armbian 提取 model_database.conf
#   2. 提取/引用 md1000 引导加载程序
#   3. 删除冗余 patch 文件
#   4. 直接注入 DTS 到内核源
#
# 用法：bash lb2004-integrate.sh

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
AMLOGIC_REPO="kemp233/amlogic-s9xxx-armbian"
KERNEL_REPO="$(cd "$SCRIPT_DIR"; pwd)"
DST_DTS="$SCRIPT_DIR/kernel-patch/beta/linux-6.1.y-rockchip-main"
DST_SRC="$SCRIPT_DIR/compile-kernel/tools/patch/linux-6.1.y-rockchip-main"

echo "# LB2004 一键整合脚本"
echo "=============================="
echo ""

# ── 1. 从 amlogic 仓库提取 model_database.conf ──
echo "## 1. model_database.conf"
CONF_PATH="build-armbian/armbian-files/common-files/etc/model_database.conf"
if ! gh api "repos/$AMLOGIC_REPO/contents/$CONF_PATH" --jq '.content' -H "Accept: application/vnd.github.raw" 2>/dev/null > /tmp/model_database.conf; then
    echo "  ❌ 无法从 $AMLOGIC_REPO 获取 $CONF_PATH"
    exit 1
fi
echo "  ✅ 已拉取 model_database.conf（$(wc -l < /tmp/model_database.conf) 行）"

# ── 2. md1000 引导加载程序准备 ──
echo ""
echo "[2] 引导加载程序 (md1000)"
echo "  从 amlogic repo 的 md1000 路径获取 armbianEnv.txt/boot.cmd/boot.scr:"
for file in armbianEnv.txt boot.cmd boot.scr; do
    gh api "repos/$AMLOGIC_REPO/contents/build-armbian/armbian-files/different-files/md1000/bootfs/$file" --jq '.content > base64decode'
    echo "    ✅ $file"
done
echo ""
echo "  idbloader.img 和 u-boot.itb 需要从 ophub Docker 编译容器中提取"
echo "  (这些不是源码中的文件，而是编译生成的二进制)"

# ── 3. 删除冗余 patch ──
echo ""
echo "[3] 清理冗余 patch 文件"
for patch in "$DST_DTS"/*.patch; do
    if [ -f "$patch" ]; then
        echo "    ❌ DELETE: $(basename "$patch")"
        rm "$patch"
    fi
done
echo "  ✅ 所有 patch 文件已删除（改用直接 DTS 注入）"

# ── 4. 编译注入脚本 ──
echo ""
echo "[4] 生成编译注入脚本"
cat > "$SCRIPT_DIR/compile-kernel/tools/patch/linux-6.1.y-rockchip-main/rk3566-lb2004.dts" <<'DTS_EOF'
// LB2004 设备树文件直接用 Docker inject 到内核源码树
// 由 lb2004-integration 脚本自动生成
// 来源: kemp233/kernel
DTS_EOF

DTS_FILE="$DST_SRC/rk3566-lb2004-bsp6.1.dts"
if [ -f "$DTS_FILE" ]; then
    echo "  ✅ LB2004 BSP DTS 文件: $(wc -l < "$DTS_FILE") 行"
else
    echo "  ⚠️ BSP DTS 文件不存在！"
    exit 1
fi

echo ""
echo "=============================="
echo "## 总结"
echo ""
echo "下一步操作："
echo "  1) model_database.td：保存到 kernelfs 的合适位置"
echo "  2) DTS 注入：直接用 Docker inject 放入内核树"
echo "  3) 引导加载程序：从 Docker 编译产物或 amlogic workflow 提取"
echo ""