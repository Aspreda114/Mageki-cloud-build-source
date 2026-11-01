# 在 Windows 上准备、用 GitHub Actions 编译未签名 IPA

## 当前交付状态

已经加入云端工作流、自动安装脚本、未签名构建配置和 IPA 结构校验程序。
**尚未执行云端编译，没有生成真实 IPA。** 当前电脑为 Windows，且尚无你的 GitHub 仓库。
首次云端运行成功、通过校验后才会发布可下载的 IPA 构建产物。

这是 Xamarin.Forms / Xamarin.iOS 的 C# 项目。编译入口是 Mono MSBuild；
原生编译、链接和资源处理使用 Apple Xcode 工具链。它不是可以直接用
`xcodebuild archive` 构建的 `.xcodeproj` 工程。

## 上传并开始构建

1. 登录 [GitHub](https://github.com/new)，创建自己的空仓库，例如 `Mageki-ios-build`。
   创建时不要勾选自动添加 README、许可证或 `.gitignore`。
   私有仓库是否有可用 Actions 额度由你的账号决定，运行前可查看账号的 Billing / Actions 设置。
2. 解压交付的 `Mageki-cloud-build-source.zip`。
   **仓库根目录必须直接包含 `.github`、`Mageki.sln`、`global.json` 和 `Mageki` 文件夹。**
   不要把 ZIP 本身上传成仓库中的一个文件，也不要多套一层 `Mageki-2.2.0` 目录。
3. 在上述目录中打开 PowerShell，执行（替换仓库地址）：

   ```powershell
   git init -b main
   git add .
   git commit -m "Configure unsigned iOS cloud build"
   git remote add origin https://github.com/你的用户名/Mageki-ios-build.git
   git push -u origin main
   ```

   首次提交若提示缺少姓名和邮箱，按 Git 提示设置你自己的提交身份，再重新提交。
   推送时使用 GitHub 登录流程；不要把密码或访问令牌写进源码。
   当前电脑已找到 Git，但可能只在 Codex 会话 PATH 中可用；若独立 PowerShell 找不到它，
   可安装 [Git for Windows](https://git-scm.com/download/win) 后重新打开终端。
4. 打开仓库的 **Actions → Build unsigned iOS IPA → Run workflow → Run workflow**。
   工作流仅手动触发，推送源码不会自动消费构建额度。
5. 构建成功后，在该次运行底部的 **Artifacts** 下载 `Mageki-iOS-unsigned`。
   解压后，真正需要的安装包是 **`Mageki-unsigned.ipa`**。
   同时提供 SHA-256 校验文件、原始 NFC 权限文件和签名说明。
6. 若运行失败，下载 `Mageki-iOS-build-logs`，保留失败步骤输出、`setup.log`、
   `build.log` 和 `build.binlog`，供后续定位。未通过校验的构建不会作为 IPA 产物上传。

也可以用 GitHub Desktop 发布解压后的目录，但务必包含隐藏的 `.github` 文件夹。

## 固定的构建环境

| 组件 | 配置 |
| --- | --- |
| GitHub runner | `macos-15-large`（x86_64） |
| Xcode | 16.2，iOS 18.2 SDK |
| Mono MDK | 6.12.0.206，包含旧版 MSBuild |
| Xamarin.iOS | 16.4.0.23 |
| .NET SDK | 5.0.214，用于旧 MSBuild 加载共享 `netstandard2.1` 项目 |
| 构建目标 | Release / iPhone / ARM64 |
| 签名 | 关闭；不需要 Secrets、Apple ID、证书或描述文件 |
| 产物最低系统 | iOS 12.0（仅修改构建用的 plist 副本） |

`global.json` 固定旧 .NET SDK，是为了避免 Mono MSBuild 意外加载云端预装的新 SDK。
无需在 Windows 上安装这些 macOS 工具。原项目的 NuGet 依赖版本保持不变。

**兼容性限制：** Xamarin 已停止维护；Xcode 16.2 与 Xamarin.iOS 16.4.0.23
不是微软官方支持的组合。这里选用仍在 macOS 15 runner 中提供的 Xcode 16.2，
并指定经典原生链接器，以尝试保留原 Xamarin 代码进行构建。
这是一套待首次云端验证的兼容构建方案，不能保证旧应用在新 iOS 上运行正常。
若出现不可兼容的 API 或链接器错误，需要根据真实日志修复，或另行迁移至现代 .NET iOS。

截至配置时（2026-10-31），GitHub 公告 macOS 14 runner 将于 2026-11-02 退役，
所以没有选用教程中常见的 `macos-13` / `macos-14`。
若未来 GitHub 移除 Xcode 16.2，脚本会明确失败，不会自动切换到可能不兼容的最新版。

## 产物与签名

- 未签名 IPA 不能直接安装；之后需要用你自己的签名方式重新签名。
- 包内标识保留 `icu.sanhei.mageki`。重签工具可能按你的账号替换它。
- 原始 iOS `Info.plist` 的版本号为 **2.1.7**，虽然源码目录名为 2.2.0；本配置不擅自修改版本号。
- 原始 `Info.plist` 的最低系统为 iOS 8.0；云端构建只在 `artifacts/Unsigned-Info.plist`
  副本中改为 iOS 12.0，以适应选用的 Xcode。原始文件保持不变。
- NFC 刷卡需要相应系统 API、硬件和具有 NFC Tag Reading 权限的签名描述文件。
  未签名构建保留 NFC 代码和原始权限文件，不能因此绕过 Apple 的权限授权。
- 本工作流面向自行重签侧载，不用于 TestFlight / App Store 提交。

## 修改位置

- `.github/workflows/ios-unsigned.yml`：手动启动、固定 runner、上传产物与日志。
- `scripts/setup-ios-ci.sh`：在一次性的云端 runner 安装 Mono 和 Xamarin，并检查版本。
- `scripts/build-ios-unsigned.sh`：构建、记录日志、校验产物并计算 SHA-256。
- `scripts/verify-ipa.py`：校验 ZIP、iPhoneOS 标识、ARM64 Mach-O、可执行权限和未签名状态。
- `build/UnsignedIpa.props`：通过 `MagekiUnsignedIpa=true` 显式启用未签名打包。

安装脚本会修改 runner 的系统工具链，因此只允许在 GitHub Actions 环境运行。
在已有工具链的 Mac 上，也可以从项目根目录运行 `bash scripts/build-ios-unsigned.sh`。

## 核实过的上游资料

- [Apple：Xcode 系统与 SDK 要求](https://developer.apple.com/xcode/system-requirements/)
- [Microsoft：Xamarin 支持生命周期](https://dotnet.microsoft.com/en-us/platform/support/policy/xamarin)
- [Xamarin.iOS 官方历史安装包](https://github.com/dotnet/macios/blob/main/DOWNLOADS.md)
- [GitHub：macOS 15 Intel 镜像软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [GitHub：macOS 14 退役公告](https://github.com/actions/runner-images/issues/13518)
- [Xamarin.iOS 16.4 的签名属性实现](https://github.com/dotnet/macios/blob/xamarin-ios-16.4.0.23/msbuild/Xamarin.Shared/Xamarin.Shared.props)
- [Xamarin.iOS 16.4 的 IPA 打包实现](https://github.com/dotnet/macios/blob/xamarin-ios-16.4.0.23/msbuild/Xamarin.iOS.Tasks/Xamarin.iOS.Common.targets)

官方 Mono 与 Xamarin 安装包地址已检查可访问；这不等同于实际编译通过。

## 本地校验记录

- 工作流通过 actionlint 静态检查；检查器旧版本不认识的 `macos-15-intel` 标签，
  已另行对照 GitHub 当前 runner 文档核实。
- 两个 Shell 脚本通过 Bash 语法解析，XML、JSON、项目引用路径和 LF 换行已检查。
- IPA 校验器通过 8 个合成样例检查：正常结构、模拟器、错误 CPU、已有签名、
  已有描述文件、缺失可执行文件、截断二进制和缺少执行权限。
  这些样例仅用于测试校验程序，不是实际应用构建。
- macOS 编译、真机安装与运行仍待云端构建及重签后验证。
