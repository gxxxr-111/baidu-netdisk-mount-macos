# baidu-netdisk-mount-macos

在 macOS 上将百度网盘挂载为 Finder 中的本地目录，无需运行百度网盘客户端。

*Mount Baidu Netdisk as a local folder in macOS Finder using OpenList, rclone and fuse-t (FSKit), via Baidu's official Open API.*

> **状态说明**：本方案仅在一台设备上完成验证（见[测试环境](#测试环境)），尚未在全新系统上进行完整的端到端安装测试。按现状提供，不提供技术支持。

## 目录

- [概述](#概述)
- [测试环境](#测试环境)
- [安装](#安装)
- [配置百度网盘凭证](#配置百度网盘凭证)
- [挂载与开机自启](#挂载与开机自启)
- [使用说明](#使用说明)
- [性能参考](#性能参考)
- [已知问题与解决方案](#已知问题与解决方案)
- [安全注意事项](#安全注意事项)
- [许可证](#许可证)

## 概述

本方案由三个开源组件组成：

```
Finder ──► fuse-t (FSKit) ──► rclone mount（VFS 缓存）──WebDAV──► OpenList（127.0.0.1）──官方 API──► 百度网盘
```

| 组件 | 作用 |
|---|---|
| [OpenList](https://github.com/OpenListTeam/OpenList) | 通过百度网盘开放 API 访问网盘，并以 WebDAV 形式在本机提供服务（AList 的社区维护分支） |
| [rclone](https://rclone.org)（官方构建） | 将 WebDAV 挂载为本地文件系统，提供读写缓存 |
| [fuse-t](https://www.fuse-t.org) | 无需内核扩展的 FUSE 实现；在 macOS 26 及以上版本使用 Apple FSKit 后端 |

挂载点为 `~/CloudDrives`，对应 OpenList 的根目录。OpenList 中的每个存储显示为一个子目录，例如 `~/CloudDrives/BaiduNetdisk`。挂载 OpenList 根目录有两个好处：

- 日后在 OpenList 中接入其他网盘时，无需修改挂载配置。
- macOS 会在卷根目录创建 `.fseventsd`、`.Trashes` 等系统目录。由于 OpenList 的根目录是虚拟目录、不接受写入，这些目录不会被同步到网盘。

## 测试环境

| 项目 | 版本或条件 |
|---|---|
| macOS | 27.0（Apple Silicon） |
| OpenList | 4.2.9（Homebrew） |
| rclone | 1.75.2（官方构建） |
| fuse-t | 1.2.9 |
| 百度网盘账号 | SVIP |
| 网络 | 中国大陆以外地区；下行约 27 MB/s，上行约 1.1 MB/s |

部分步骤针对 OpenList 4.2.9 的特定行为（见[已知问题与解决方案](#已知问题与解决方案)），其他版本可能不再需要，也可能失效。

## 安装

**前提条件**：macOS 26 或更高版本（FSKit 后端需要）、[Homebrew](https://brew.sh)、百度网盘 SVIP 账号。

1. 安装 OpenList 和 fuse-t。安装 fuse-t 需要输入管理员密码。

   ```bash
   brew install openlist
   brew install --cask macos-fuse-t/homebrew-cask/fuse-t
   ```

2. 打开 **系统设置 → 通用 → 登录项与扩展 → 文件系统扩展**。如果列表中有 fuse-t，将其启用。

3. 初始化 OpenList。脚本会将服务限定为只监听本机、创建管理员账户并授予 WebDAV 写权限，管理员密码保存在 `~/.config/openlist/admin-password.txt`。

   ```bash
   scripts/setup-openlist.sh
   ```

4. 启动 OpenList（暂时在前台运行），然后在另一个终端中创建百度网盘存储，并配置 rclone。

   ```bash
   openlist server --data ~/.config/openlist
   ```

   ```bash
   python3 scripts/configure-baidu-storage.py
   scripts/setup-rclone.sh
   ```

   - `configure-baidu-storage.py`：创建存储并写入调优后的参数，但不会写入凭证；凭证需按下一节手动填写。
   - `setup-rclone.sh`：Homebrew 提供的 rclone 不包含 `mount` 子命令，因此脚本会下载 rclone 官方构建，并创建名为 `openlist` 的 WebDAV 远程。

## 配置百度网盘凭证

本方案使用 OpenList 提供的在线 API 获取和刷新 refresh token。

1. 访问 <https://api.oplist.org/>，选择 **百度网盘**，以 **OpenList 在线 API** 方式获取 Token，在百度授权页面登录并确认授权，然后复制返回的 `refresh_token`。
2. 复制管理员密码：

   ```bash
   pbcopy < ~/.config/openlist/admin-password.txt
   ```

3. 访问 <http://127.0.0.1:5244>，以用户名 `admin` 登录，进入 **管理 → 存储 → /BaiduNetdisk → 编辑**，填入 `refresh_token` 并保存。存储状态显示为 `work` 即表示配置成功。

### 关于自建开放平台应用

百度网盘开放平台允许完成个人实名认证的开发者创建 1 个应用，不需要企业认证。但根据[官方文档](https://pan.baidu.com/union/doc/%E4%BD%BF%E7%94%A8%E5%85%A5%E9%97%A8/%E5%88%9B%E5%BB%BA%E5%BA%94%E7%94%A8/)，2026 年 6 月 3 日之后创建的应用，其下载、上传、移动、列目录等接口只能访问 `/apps/{应用名}` 目录，无法用于挂载整个网盘。

在线 API 使用的是 OpenList 项目较早创建的应用，不受此限制。代价是 token 刷新请求需要经过第三方服务器 `api.oplist.org`。

## 挂载与开机自启

先在前台运行挂载脚本，确认挂载正常：

```bash
cp config/mount-filter.txt scripts/mount-baidu.sh ~/.config/rclone/
~/.config/rclone/mount-baidu.sh
```

确认无误后，安装 LaunchAgent。登录后会自动启动 OpenList 和挂载，进程异常退出时自动重启：

```bash
scripts/install-launchd.sh
```

取消开机自启（配置、缓存和凭证会保留）：

```bash
scripts/uninstall-launchd.sh
```

挂载脚本的主要参数可以通过环境变量覆盖，例如 `MOUNT_POINT`、`REMOTE`、`FUSE_BACKEND`（取值为 `fskit` 或 `nfs`），详见 `scripts/mount-baidu.sh`。

## 使用说明

| 操作 | 行为 |
|---|---|
| 浏览目录 | 目录列表缓存 5 分钟（`--dir-cache-time`），其他设备上的改动可能延迟显示。 |
| 读取文件 | 按需分块下载并写入本地缓存（上限 30 GB，保留 7 天）；再次读取时直接从缓存提供。 |
| 写入文件 | 先写入本地缓存，约 10 秒后在后台上传。百度网盘不支持部分更新，修改文件会重新上传整个文件。 |
| 删除文件 | 文件直接从网盘删除并进入百度网盘回收站，不会保留在 `.Trashes` 中。 |
| 在 `~/CloudDrives` 根目录写入 | 会被拒绝。文件需放在具体存储的目录中，例如 `~/CloudDrives/BaiduNetdisk`。 |

**建议**：

- 断开网络或让电脑进入睡眠前，确认后台上传已完成，即日志中出现 `upload succeeded`：

  ```bash
  tail -f ~/.config/rclone/mount.log
  ```

- 不要在挂载目录中直接存放或打开 Git 仓库、依赖目录（如 `node_modules`、`.venv`）、数据库文件，也不要使用会频繁自动保存的应用。这类场景会产生大量小文件读写和重命名，在网盘上既慢又容易出错。建议项目放在本地磁盘，挂载目录仅用于存档和传输。
- 通过 API 上传的文件不会出现在百度网盘 App 的"最近"页面中，请在"全部文件"中下拉刷新查看。

## 性能参考

以下数据在[测试环境](#测试环境)中测得，仅供参考。

| 操作 | 速度 |
|---|---|
| 在 Finder 中首次读取文件 | 约 23 MB/s |
| 读取已缓存的文件 | 100 MB/s 以上 |
| 通过挂载目录上传 | 0.6–1.3 MB/s（受本地上行带宽限制） |
| `rclone copy` 下载（16 个连接） | 约 17 MB/s |

官方下载接口对 SVIP 账号不限速；普通 VIP 及非会员账号的下载速度会受到限制。

## 已知问题与解决方案

### OpenList 初始化时未创建管理员账户

- **现象**：使用 admin 登录返回 401，数据库中只有 guest 用户。
- **原因**：OpenList 4.2.9 首次启动时可能不会创建管理员账户。
- **解决**：首次启动时设置环境变量 `OPENLIST_ADMIN_PASSWORD`。`setup-openlist.sh` 已包含此步骤。

### WebDAV 写入返回 403

- **现象**：`MKCOL`、`PUT` 请求返回 403 Forbidden。
- **原因**：管理员账户缺少 WebDAV 管理权限（权限位 9–11）。
- **解决**：将权限值与 `3584` 按位或。`setup-openlist.sh` 已包含此步骤。

### 上传失败，日志显示超时

- **现象**：上传返回 405，OpenList 日志中出现 `Client.Timeout exceeded`。
- **原因**：每个上传分片默认须在 60 秒内完成，上行带宽较低或网络延迟较高时会超时。
- **解决**：启用低带宽上传模式（使用最小分片），将上传线程设为 8、超时设为 300 秒。`configure-baidu-storage.py` 已包含这些设置。

### Finder 中读取速度偏低

- **现象**：读取速度只有 2–3 MB/s。
- **原因**：在高延迟网络下，单个连接的速度约为 2 MB/s。
- **解决**：使用 `--vfs-read-chunk-streams 16 --vfs-read-chunk-size 8M` 并行读取。挂载脚本已采用此配置。

### 卸载后立即重新挂载失败

- **现象**：日志显示 `mount stopped before calling Init`。
- **原因**：上一次挂载的 FSKit 资源尚未释放。
- **解决**：等待数秒后再挂载。

### `install-launchd.sh` 提示 `Bootstrap failed: 5`

- **原因**：`launchctl bootout` 返回时旧任务尚未完全退出，此时立即执行 bootstrap 会失败。
- **解决**：脚本会等待旧任务退出后再重新加载。

### 日志中周期性出现 `.fseventsd` 上传错误

- **原因**：macOS 在挂载根目录创建 `.fseventsd`，而 OpenList 的虚拟根目录拒绝写入（409）。rclone 会按退避间隔重试。
- **影响**：这是挂载 OpenList 根目录的预期结果，可以忽略。

### 0 字节文件无法上传

- **原因**：OpenList 的百度网盘驱动不支持上传空文件，此类文件只保留在本地缓存中。

### 部分进程无法复制带 `com.apple.quarantine` 属性的文件

- **现象**：在受沙盒限制的进程中复制此类文件时，目标文件为 0 字节。
- **影响**：在 Finder 中拖拽复制不受影响。

## 安全注意事项

- OpenList 仅监听 `127.0.0.1:5244`，不对局域网开放。
- 以下文件包含凭证，请勿提交到版本控制系统或分享给他人（`.gitignore` 已排除其中可匹配的文件）：

  | 文件 | 内容 |
  |---|---|
  | `~/.config/openlist/data.db` | 百度网盘 refresh token |
  | `~/.config/openlist/admin-password.txt` | OpenList 管理员密码 |
  | `~/.config/rclone/rclone.conf` | 经过混淆但可还原的密码 |
  | `~/.config/openlist/log/` | 可能包含明文的百度 access token |

- 不建议使用 OpenList 的 `crack` 下载模式或其他第三方破解工具。这类方式违反百度网盘用户协议，可能导致账号被限制或封禁。

## 许可证

[MIT](LICENSE)
