# kemp233/amlogic-s9xxx-armbian 三大核心文件分析

> 分析时间：2026-07-31
> 仓库：https://github.com/kemp233/amlogic-s9xxx-armbian

---

## 一、三个文件的角色与关系

```
                    GitHub Actions Workflow
                    (compile-kernel.yml)
                            │
                            │  uses: ophub/amlogic-s9xxx-armbian@main
                            ▼
                    ┌──────────────────┐
                    │   action.yml     │  ← GitHub Composite Action
                    │   (入口调度层)    │     决定走 armbian 还是 kernel 分支
                    └──────┬───────────┘
                           │
              ┌────────────┴────────────┐
              │ build_target == "kernel"│
              ▼                         │
     ┌──────────────┐          build_target == "armbian"
     │  recompile    │                   │
     │ (内核编译入口) │                   ▼
     └──────┬───────┘          ┌──────────────┐
            │                  │    rebuild    │
            │ Docker 容器       │ (镜像构建入口)  │
            ▼                  └──────────────┘
     ┌───────────────────┐
     │ armbian_compile_   │
     │ kernel.sh          │  ← 容器内的 Agnel 编译脚本
     │ (~1500行 Bash)      │
     └───────────────────┘
```

---

## 2. action.yml——调度层

### 位置
根目录 `action.yml`

### 类型
GitHub **Composite Action** (`runs.using: "composite"`)

### 职责
接受 workflow 传入的所有参数，根据 `build_target` 分发到两条路径：

| build_target | 入口 | 操作 |
|:---|:---|:---|
| `kernel` | `sudo ./recompile` | 内核编译 |
| `armbian` | `sudo ./rebuild` | Armbian 镜像重建 |

### 完整输入参数

| 参数 | 默认 | 说明 | recompile 导入? | rebuild 导入? |
|:---|:---|:---|:---|:---|
| build_target | armbian | 编译目标（armbian/kernel） | — | — |
| kernel_source | unifreq | 内核源码仓库 | ✅ -r | — |
| kernel_repo | opt/kernel | 内核发布仓库 | — | ✅ -r |
| kernel_usage | stable | 内核标签 | — | ✅ -u |
| armbian_kernel | 6.1.y_6.12.y | 内核版本范围 | — | ✅ -k |
| kernel_kernel | 6.1.y_6.12.y | 内核版放范围 | ✅ k | — |
| kernel_auto | true | 自动最新内核 | ✅ -a | ✅ -a |
| kernel_package | all | 编译范围 (all/dtbs) | ✅ -a | — |
| kernel_sign | -ophub | 内核签名 | ✅ -n | — |
| kernel_toolchain | clanging | 编译器选择 | ✅ -t | — |
| config_flavor | — | 内核配置 flavor 标识 | ✅ -f (`armar_compile_kerl.sh`内) | — |
| kernel_config | false | 外部 .config 路径 | action 内 cp | — |
| **kernel_patch** | **false** | **自定义补丁目录** | **action 内 cp** | — |
| **auto_patch** | **false** | **启用补丁应用** | ✅ **-p** | — |
| delete_source | false | 删除源码 | ✅ -d | — |
| ccache_clear | false | 清除 ccache | ✅ -c | — |
| docker_hostpath | '' | Docker 挂载目录 | ✅ -h | — |
| docker_image | '' | Docker 镜像 | ✅ -i | — |

### 补丁导入的关键代码

```bash
custom_kernel_patch="compile-kernel/tools/patch"
if [[ -n "${{ inputs.kernel_patch }}" && "${{ inputs.kernel_patch }}" != "false" ]]; then
    if [[ -d "${{ github.workspace }}/${{ inputs.kernel_patch }}" ]]; then
        rm -rf ${custom_kernel_patch}/* 2>/dev/null && sync
        cp -vrf "${{ github.workspace }}/${{ inputs.kernel_patch }}/." -t "${custom_kernel_patch}/" || true
    fi
fi
```

**关键残留——action 先在内部清空 `./compile-kernel/tools/patch/`，逐文件复制**。岁月们在 workflow 里传入 `kernel_patch: compile-kernel/tools/patch`（仓库相对路径），action 会做：
```bash
cp -vrf "/home/runner/work/amlogic-s9xxx-armbian/compile-kernel/tools/patch/."
       → "compile-kernel/tools/patch/"
```

**这等于把整个 repo 的 `compile-kernel/tools/patch/` 里所有文件和子目录都复制到 action 执行目录的 `compile-kernel/tools/patch/`。` 然后调用 `recompile -p true ...` 时，armbian_compile_kernel.sh 从 `$kernel_patch_path/${local_kernel_path}` 去找 `.patch` 文件。

### recompile 的完整参数海绵

```
sudo ./recompile
  -r "${kernel_source}"       → repo source
  -k "${kernel_version}"     → kernel version
  -a "${kernel_auto}"        → auto latest kernel
  -m "${kernel_package}"     → all/dtbs
  -p "${auto_patch}"         → enable patch apply（true/false）
  -n "${kernel_sign}"        → custom sign
  -t "${kernel_toolchain}"   → toolchain
  -a "${compress_format}"    → initrd compression
  -d "${delete_source}"      → delete source
  -s "${silent_log}"         → silent log
  -c "${ccache_clear}"       → ccache clear
  -f "${config_flavor}"      → config flavor
  -l "${enable_log}"          → enable log
  -h "${docker_hostpath}"    → docker mount
  -i "${docker_image}"       → docker image
```

---

## 3. release（内核编译入口）

### 位置
根目录 `release`

### 四个阶段

```bash
init_var "${@}"
  ↓ 解析参数：只保留自己的参数 (-h -i)，忽略编译相关参数 (-k -a -n -m -p -r -t -c -d -s -z -l -f)
  ↓
install_docker_engine()
  ↓ 如果 docker 未安装，安装 Docker
  ↓
launch_docker_container()
  ↓ 启动 ophub/armbian-$docker_image:arm64 容器
  ↓ 挂载卷：
  ↓   ${docker_hostpath}/compile-kernel  → /opt/kernel/compile-kernel
  ↓   ${docker_hostpath}/ccache          → /root/.ccache
  ↓
configure_and_and_compile()
  ↓ 1. docker exec ... -u    （在容器内同步 armbian kernel 脚本）
  ↓ 2. docker cp config/     （注入内核配置 .config！）
  ↓ 3. docker cp patch/      （注入补丁！）
  ↓ 4. docker exec ... bash /usr/sbin/armbian-complete_sh "${@}" （传入所有原始参数）
```

### docker cp 关键代码

```bash
# 第 162 行
[[ -d "${config_path}" ]] && docker cp ${config_path}/. "${docker_container}":/opt/kernel/compile-kernel/tools/config/
[[ -d "${kernel_patch_path}" ]] && docker cp ${kernel_patch_path}/. "${docker_container}":/opt/kernel/compile-kernel/tools/patch/
```

⚠️ **重要！** `release` 硬编码了 config 和 patch 从本地目录 `compile-kernel/tools/config/` 和 `compile-kernel/tools/patch/` 复制到容器内。

### 参数传法

```bash
docker exec -i "${docker_container}" bash "${docker_script}" "${@}"
```

**这里 `${@}` 是 release 自己收到的所有原始参数**（包括 -k -r -m -p 等），直接传给容器的 `/usr/sbin/armbian-complete-kernel`。然后容器内部脚本完全基于这些参数执行。

---

## 4. rebuild（armbian 镜像构建入口）

### 位置
`rebuild`

### 功能
从现有的 Armbian 镜像文件（.img）出发，替换内核+uboot+设备树，重新构建为适配特定设备的 Armbian 镜像。

### init_var 参数

```bash
-b $\rightarrow$ 设备选择（主板名/型号）
-r $\rightarrow$ 内核发布仓库（kernel_repo）
-u $\rightarrow$ 内核标签（kernel_usage）
-k $\rightarrow$ 内核版本列表
-a $\rightarrow$ 自动最新内核
-t $\rightarrow$ rootfs类型（ext4/btrfs)
-s $\rightarrow$ 镜像大小
-n $\rightarrow$ 构建者签名
```

### 工作流程

```
model_database.conf 解析设备数据库
  → 下载内核文件 (从 kemp233/kernel release)
  → 下载 uboot 文件 (从 kemp233/u-boot)
  → 下载 firmware (从 kephub/firmware)
  → 提取 Armbian 镜像
  → 挂载 bootfs /rootfs分区
  → 替换内核、uboot、设备树
  → 重组写出 .img.gz 文件
```

**rebuild 本身不编译内核——它从 release 下载预编译的内核包。**

---

## 5. 完整数据流——LB2004 案例

### 内核编译（compile-kernel.yml 触发）

```
workflow: compile-kernel.yml
  ↓ 传入：source=unifreq, version=6.1.y, package=dtbs, kernel_patch=compil=kernel/tools/patch, auto_patch=true
  ↓
action.yml (build_target=kernel)
  ↓
sudo ./recompile -r unifreq -k 6.1.y -m dtbs -p true ...
  ↓
  ├─ ① launch_docker_container → 启动 armbian Docker 容器
  ↓
  ├─ ② docker cp compile-kernel/tools/patch/ → 容器内的 /opt/kernel/compile-kernel/tools/patch/
  ↓   (这个patch/ 目录下包括我们的 linux-6.1.y/ 子目录！
  ↓
  ├─ ③ docker exec 容器 bash armbian">kernel -r unifreq -k 6.1.y -m dtbs -p true...
  ↓
  ├─ 容器内 armbian_compile_kernel.sh：
  ↓   ├─ 解析 -k 6.1.y → MAIN_LINE=6.1 → local_kernel_path="linux-6.1.y"
  ↓   ├─ 解析 -r unifreq → code_owner="unifreq", code_repo=""
  ↓   ├─ get_kernel_source() → git clone unifreq/linux-6.1.y-rockchip@main
  ↓   ├─ apply_patch() → 从 /opt/kernel/compile-kernel/tools/patch/linux-6.1.y/ 复制 .patch 文件
  ↓   ├─ patch -p1 ＜ 400-dts-lb2004.patch     （创建 DTS）
  ↓   ├─ patch -p1 ＜ 400-dts-add-rk3566-lb2004.patch  （Makefile 条目）
  ↓   ├─ compile_dtbs() → make dtbs -j{nproc}
  ↓   └─ packit_dtbs() → dtb-rockchip.tar.gz 包含 rk3566-lb2004.dtb
  ↓
  ├─ Upload to Release → 释放到 GitHub Release
```

### Armbian 完整镜像构建

```
rebuild（完整 Armbian 镜像构建构建）
  ↓
model_database.conf  → 读取 lb2004 设备信息
  ↓
  ├─ 从 kemp233/kernel release 下载内核包（含 rk3566-lb2004.dtb）
  ├─ 从 kemp233/u-boot 发布下载 bootloader（idbloader.img + u-boot.itb）
  ├─ 从 ophub/fir\nware 下载固件文件
  ↓
提取 Armbian 基础镜像 → 挂载分区
  ↓
  ├─ 替换内核 + 模块
  ├─ 替换设备树
  ├─ 安装 bootloader
  ├─ 恢复 rootfs 文件
  ↓
输出：Armbian 镜像 .img.gz
```

---

## 6. LB2004 接入需要的文件汇总

| 文件 | 位置 | 文件名 | 参数 | 状态 |
|:--|:---|:---|:---|:---|
| Makefile entry patch | compile-kernel/tools/patch/linux-6.1.y/ | 400-dts-add-rk3566-lb2004.patch | GNU patch 格式 | ✅ |
| DTS patch | compile-kernel/tools/patch/linux-6.1.y/ | 400-dts-lb2004.patch | diff -u /dev/null 格式 | ✅ |
| workflow 参数 | compile-kernel.yml | kernel_patch: compile-kernel/tools/patch, auto_patch: true | 向 Action 传参 | ❌ 见下 |
| model_database.conf | build-armbian/common-files/etc/ | model_database.conf（r312） | kb2004 设备定义 | ✅ |
| bootloader | kemp233/u-boot | idbloader.img + u-boot.itb ) | uboot 引导文件 | ✅ |

### ⚠️ 当前问题

compile-kernel.yml 写入了 `kernel_patch: compile-kernel/tools/patch` 和 `auto_patch: true`，但两个 runs 的 dtb 都没有出。

**hyper 猜测：DTS BSP 节点编译失败**——unifreq/linux-6.1.y-rockchip 头文件中缺少很多 LB2004 BSP 独有节点（npr related, can HW, etc），DTC 编译时 failed 了。需要查看编译日志获取具体的 DTC 报错。

**下一步：获取完整 run 日志检查 DTC 输出。**