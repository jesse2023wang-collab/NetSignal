# NetSignal - macOS 网络状态监测工具

<p align="center">
  <img src="screenshots/菜单栏.png" alt="NetSignal 面板" width="360">
</p>

NetSignal 是一款 macOS 菜单栏应用，通过监测国内外主要网站的访问速度，用直观的信号格图标反映当前网络状态。点击菜单栏图标弹出监控面板，实时展示各网站延迟与彩色进度条。

<p align="center">
  <img src="screenshots/菜单栏-图标-非彩色.png" alt="非彩色图标" height="50">
  <img src="screenshots/菜单栏-图标-彩色.png" alt="彩色图标" height="50">
</p>
<p align="center"><small>非彩色 / 彩色</small></p>

<p align="center">
  <img src="screenshots/设置页-自定义网址.png" alt="设置页" width="360">
</p>

## 特性

- **监控面板**：点击菜单栏图标弹出面板，一目了然查看网络状态
- **延迟可视化**：每个网站显示响应时间 + 彩色进度条（绿/橙/红），一眼区分快慢
- **信号格图标**：菜单栏图标 1-4 格直观展示网络好坏
- **环境切换**：面板顶部药丸控件一键切换「仅国内」/「全球」模式
- **国内外区分**：同时监测国内网站（微博、小红书、京东、淘宝、B站、网易）和海外网站（X、YouTube、Google、Netflix、GitHub）
- **实时测速**：HEAD 请求测量网站响应时间（DNS + 连接 + 首字节），HEAD 失败自动 GET fallback
- **自动刷新**：支持自定义刷新间隔（10-300 秒），面板内显示倒计时
- **自定义网站**：设置面板内添加、删除监测网站，卡片式布局
- **开机启动**：支持开机自启动（SMAppService + LaunchAgent 兼容）
- **免费开源**：所有功能免费使用，无需付费

## 下载安装

- **GitHub Releases**：[v1.0.2 下载](https://github.com/jesse2023wang-ai/NetSignal/releases/tag/v1.0.2)（NetSignal-1.0.2.dmg）
- 下载后打开 `.dmg`，将 NetSignal 拖入 Applications 文件夹即可

## 版本日志

详见 [CHANGELOG.md](CHANGELOG.md)。

## 首次运行设置

macOS 默认只允许运行已签名的应用。NetSignal 作为开源软件，首次运行前需要开启「任何来源」：

### 1. 打开终端，执行以下命令

```bash
sudo spctl --master-disable
```

输入开机密码后生效。

### 2. 确认设置

打开 **系统设置 → 隐私与安全性**，在「安全性」区域应显示：

```
允许从以下位置下载的应用程序：
  ● App Store
  ○ App Store 和被认可的开发者
  ○ 任何来源  ← 已选中
```

### 3. 首次运行

- 打开 Applications 文件夹，**右键** NetSignal → **打开**
- 弹出确认框时点「打开」

> 如果仍然提示"无法打开"或"已损坏"，可以执行以下命令解除隔离属性：
> ```bash
> sudo xattr -rd com.apple.quarantine /Applications/NetSignal.app
> ```

### 关闭「任何来源」（可选）

安装完成后如需恢复 macOS 默认安全设置：

```bash
sudo spctl --master-enable
```

执行后「任何来源」选项将隐藏，但不影响已安装的 NetSignal 正常运行。

## 测速标准

| 响应时间 | 状态 | 进度条颜色 |
|---------|------|-----------|
| < 500ms | 良好 | 绿色 |
| 500-1500ms | 一般 | 橙色 |
| > 1500ms | 较慢 | 红色 |
| 超时 | 超时 | 灰色 |

## 信号格规则

| 平均响应时间 | 信号格 | 描述 |
|------------|-------|------|
| < 200ms | 4格 | 网络极佳 |
| 200-500ms | 3格 | 网络良好 |
| 500-1500ms | 2格 | 网络一般 |
| > 1500ms | 1格 | 网络较差 |
| 全部超时 | 0格 | 无网络 |

## 使用

- **点击菜单栏图标**：弹出监控面板
- **面板内操作**：
  - 顶部药丸控件切换「仅国内」/「全球」模式
  - 查看各网站延迟与彩色进度条
  - 点击「立即刷新」手动测速
  - 点击齿轮图标进入设置面板
  - 底部「退出 NetSignal」退出应用
- **设置面板**：
  - 开机自动启动、自动刷新开关
  - 刷新间隔滑块（10-300 秒）
  - 网站列表管理（添加、删除）

## 构建

```bash
cd NetSignal
swift build --disable-sandbox -c release
bash build.sh   # 编译 + 打包 DMG
```

## 与竞品的区别

| 功能 | Ethernet Status | NetSignal |
|------|----------------|-----------|
| 菜单栏显示 | 支持 | 支持 |
| 信号格图标 | 不支持 | 支持 |
| 监控面板（Popover） | 不支持 | 支持 |
| 延迟进度条可视化 | 不支持 | 支持 |
| 国内外网站测速 | 不支持 | 支持 |
| 环境一键切换 | 不支持 | 支持 |
| 自定义网站 | 不支持 | 支持 |
| 高级功能付费 | 是 | 否（全部免费） |

## 技术栈

- **语言**：Swift 5.9+
- **UI 框架**：纯 AppKit（NSPopover + NSView 手写布局）
- **构建**：Swift Package Manager
- **设计系统**：自定义 Design Tokens（颜色、字体、间距）
- **最低系统**：macOS 13.0+

## 许可证

MIT License
