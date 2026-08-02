# LB2004 DTB 生成根因分析

> 分析时间：2026-07-31 16:55 UTC
> 基于：run 30646557707（kemp233/amlogic-s9xxx-armbian, commit f21b9eb）

## Run 30646557707 日志结果

| 检查项 | 结果 |
|:---|:---|
| 日志获取 | ❌ GitHub ARM runner zip 损坏(vp/invalid zip) |
| Release 6.1.180.tar.gz | ✅ 发布成功，3.8MB |
| dtb-rockchip-6.1.180-ophub.tar.gz 内含 lb2004.dtb | ❌ **未找到！** |
| dtb-rockchip 含 orangepi-3b | ❌ 没有 |
| dtb-rockchip 含 panther-x2 | ✅ 有 |

## 🔴 根本结论：patch 的 Makefile 条目没有被编译系统识别

### 两个独立验证

**证据 1：orangepi-3b dtb 缺失**
- unifreq/linux-6.1.y-rockchip Makefile 里确实有 orangepi-3b dtb 条目（第 195 行）
- 编译输出中 **没有被包含在内**
- 说明 handware 的是主线 unifreq 仓库，不是 BSP 内核仓库！
- unifreq/linux-6.1.y 主线内核没有 orangepi-3b 的 DTS → 这也是为什么 orangepi-3b 不出现

**证据 2：`kernel_source=unifreq` 导致 clone 主线内核**
- `apply_patch()` 只对主线内核有用
- 主线内核的 arch/arm64/boot/dts/rockchip/Makefile 中没有 orangepi-3b 和 lb2004 条目
- 我们的 patch 会添加条目，但组件树中的 BSP DTS 引用节点在主线 .dtsi 中不存在 → DTC 编译失败

### 为何 kemp233/kernel 的 compile-rockchip-rk35xx-kernel.yml 能成功

kemp233/kernel 中 workflow 核心差异：

```yaml
kernel_source: unifreq/linux-6.1.y-rockchip
```

而 amlogic-s9xxx-armbian 中：

```yaml
kernel_source: unifreq
```

`unifreq/linux-6.1.y-rockchip` 含有 BSP 头文件（完整 rockchip DTSI），而 `unifreq` 只有主线 clean。

## 🎯 修复方案

### 方案 A：修复 amlogic 仓库的 kernel_source

在 compile-kernel.yml 的 workflow denos 中，把 `kernel_source` 的传入改为 `unifreq/linux-6.1.y-rockchip`。

**但** workfoo 的 `kernel_source` 只接受两个值：`unifreq`/`ophub`。需要改为自定义值。

### 方案 B（推荐）：从 kemp233/kernel 独立编译

kemp233/kernel 的 `compile-rockchip-rk35xx-kernel.yml` 已经能成功编译 lb2004.dtb——  
它的 Docker inject 探针方案已经证明了可行。

只需：
1. 在 kemp233/kernel 中触发其自行编译 dtbs
2. dtb 文件 autom over to amlogic-kernel releases
3. amlogic 的 rebuild 脚本从 kemp233/kernel release 下载 dtb

**行入点**：

| 步骤 | 做什么 | 效果 |
|:---|:---|:---|
| 1 | kemp233/kernel workflow 设置 `prick_psanter: dtbs` | 只编译 dtb（17mm，不加超时）|
| 2 | 在工作流中加 Upload to Release | dtb 上传 kemp233/kernel release |
| 3 | amlogic model_database.conf 指向 kemp233/kernel 的 dtb | 通过 rebuild 脚本新建镜像 |

---

## 🚀 立即行动

不继续折腾 amlogic 复杂的 ophub-specific 编译环境。**用 kemp233/kernel 直接保存子步骤 1+2**。

现在 codebase 现状：
- `./.github/manifest-files/compile-rockchip-rk35xx-kernel.yml`：已有 Complete + Rescue + Audit + Upload
- `./kernel-patch/beta/linux-6.1.y-rockchip-main/`：有 patch + DTS 文件
- Release tag `kernel_rk35xx`：可上传 dtb 最终文件