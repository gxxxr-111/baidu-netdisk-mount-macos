# 在 macOS Finder 中挂载百度网盘

把百度网盘挂载成 Finder 里的一个文件夹（`~/CloudDrives/BaiduNetdisk`），不用开百度网盘 App 就能打开、拖拽上传和下载。全部基于开源组件，走百度**官方开放 API**。

挂载的是 OpenList 的根目录，每个存储是 `~/CloudDrives` 下的一个子文件夹。这样以后接入阿里云盘、115 等，也会并排出现在这里。另一个好处是：macOS 自动在卷根目录创建的 `.fseventsd`、`.Trashes` 会被 OpenList 的虚拟根目录拒绝写入，不会出现在网盘里。

```
Finder ──► fuse-t (FSKit) ──► rclone mount (VFS 缓存) ──WebDAV──► OpenList (127.0.0.1) ──官方 API──► 百度网盘
```

| 组件 | 作用 |
|---|---|
| [OpenList](https://github.com/OpenListTeam/OpenList) | 把百度网盘转成本地 WebDAV（AList 的社区分支） |
| [rclone](https://rclone.org) 官方版 | 把 WebDAV 挂载成文件系统，带本地缓存 |
| [fuse-t](https://www.fuse-t.org) | 不需要内核扩展的 FUSE；macOS 26 及以上可用 FSKit 后端 |

## 实测（SVIP，境外网络：下行约 27 MB/s，上行约 1.1 MB/s）

| 操作 | 速度 |
|---|---|
| 在 Finder 里读取或复制网盘文件（第一次） | 约 23 MB/s |
| 再次读取已缓存的文件 | 100 MB/s 以上 |
| 拖拽上传 | 0.6–1.3 MB/s（受本地上行带宽限制） |
| `rclone copy` 用 16 个连接下载 | 约 17 MB/s |

下载满速需要 **SVIP**：官方下载接口对普通 VIP 会限速。

## 安装

前提：macOS 26 或以上（FSKit）、Homebrew、百度网盘 SVIP。

```bash
brew install openlist
brew install --cask macos-fuse-t/homebrew-cask/fuse-t   # 需要管理员密码
```

装完后，打开 **系统设置 → 通用 → 登录项与扩展 → 文件系统扩展**，如果里面有 fuse-t，把它打开。

```bash
scripts/setup-openlist.sh                 # 初始化：只监听本机、创建管理员、开启 WebDAV 写权限
openlist server --data ~/.config/openlist # 先在前台运行，配置完可改用 launchd
python3 scripts/configure-baidu-storage.py
scripts/setup-rclone.sh
```

### 获取百度凭证（refresh token）

1. 打开 https://api.oplist.org/ ，选 **百度网盘**，用 **OpenList 在线 API** 的方式获取 Token，在百度页面登录并授权。
2. 复制管理员密码：`pbcopy < ~/.config/openlist/admin-password.txt`
3. 打开 http://127.0.0.1:5244 ，用户名 `admin`，进入 **管理 → 存储 → /BaiduNetdisk → 编辑**，粘贴 refresh_token 后保存。状态显示 `work` 就成功了。

> **为什么不用自己创建的开放平台应用？** 个人实名认证可以创建 1 个应用，不需要企业认证。但 2026-06-03 之后新建的应用，下载、上传等接口**只能访问 `/apps/应用名` 目录**，看不到网盘里的其他文件。在线 API 用的是 OpenList 项目早年创建的应用，代价是刷新 token 时要经过 api.oplist.org 这个第三方服务器。

### 挂载

```bash
cp scripts/mount-baidu.sh ~/.config/rclone/ && ~/.config/rclone/mount-baidu.sh   # 前台测试
scripts/install-launchd.sh     # 开机自启 OpenList 和挂载
scripts/uninstall-launchd.sh   # 取消自启
```

## 使用时的行为

- **浏览目录**：目录列表缓存 5 分钟（`--dir-cache-time`），在别的设备上新增的文件不会马上出现。
- **打开文件**：读到哪部分就下载哪部分，存进本地缓存（最多 30 GB，保留 7 天），之后再打开就是本地速度。
- **写入或保存**：先写进本地缓存，10 秒后在后台上传。百度不支持只改文件的一部分，**改一个字节也会重新上传整个文件**。合盖或断网前，用 `tail -f ~/.config/rclone/mount.log` 确认出现 `upload succeeded`。
- **不要**直接在挂载盘上打开 git 仓库、代码项目（`node_modules`、`.venv`）、数据库，也不要用 Office 自动保存。项目放本地磁盘，挂载盘只用来存档。
- **手机上看不到新上传的文件**：通过 API 上传的文件不会出现在 App 的"最近"页。去 **全部文件** 下拉刷新。

## 踩过的坑

| 现象 | 原因和解决 |
|---|---|
| 管理员登录 401，数据库里只有 guest 用户 | OpenList 4.2.9 第一次启动有时不创建 admin。解决：首次启动时设置 `OPENLIST_ADMIN_PASSWORD` 环境变量（`setup-openlist.sh` 已经处理）。 |
| WebDAV 的 `MKCOL`/`PUT` 返回 403 | admin 缺少 WebDAV 管理权限位（第 9–11 位）。解决：`permission \| 3584`。 |
| 上传报 405，日志里是 `Client.Timeout exceeded` | 每个分片默认要在 60 秒内传完，境外上行慢就会超时。解决：开低带宽模式（小分片）、8 线程、300 秒超时。 |
| Finder 读取只有 2–3 MB/s | 单个连接到百度大约 2 MB/s。解决：`--vfs-read-chunk-streams 16 --vfs-read-chunk-size 8M`。 |
| 刚卸载就重新挂载失败（`mount stopped before calling Init`） | FSKit 还没释放。等几秒再挂载。 |
| 网盘根目录出现 `.fseventsd`、`.Trashes` | macOS 会在每个卷的根目录创建它们，排除规则拦不住。解决：挂载 OpenList 根目录（`REMOTE=openlist:`），它们落在虚拟根目录里，写入会被拒绝（409）。代价是 rclone 日志里会按退避间隔周期性出现一条 `.fseventsd` 的上传错误，可以忽略。 |
| 在 Finder 里删除挂载盘上的文件 | 不会留在 `.Trashes` 里，而是直接删除（进入百度回收站）。 |
| `install-launchd.sh` 报 `Bootstrap failed: 5` | `launchctl bootout` 返回时旧任务还没完全退出，马上 bootstrap 就会失败。脚本现在会先等旧任务退出。 |
| 0 字节文件上传 405 | OpenList 百度驱动不支持空文件，空文件只会留在本地。 |
| 沙盒里的终端或程序复制带 `com.apple.quarantine` 的文件失败 | 和沙盒环境有关，Finder 拖拽正常。 |
| Homebrew 版 rclone 没有 `mount` | 用 rclone 官网的二进制版本（`setup-rclone.sh` 会自动下载）。 |

## 安全

- OpenList 只监听 `127.0.0.1:5244`。
- **不要提交**以下文件（`.gitignore` 已经排除）：
  - `~/.config/openlist/data.db`：里面有 refresh token
  - `admin-password.txt`
  - `~/.config/rclone/rclone.conf`：密码只是混淆，可以还原
  - 各种日志：OpenList 日志里有明文百度 access token
- 不建议用 crack 下载模式或其他破解工具：违反百度用户协议，有封号风险。
