# BrightnessFollow / 亮度跟随

一个专注于 macOS 外接显示器亮度联动的菜单栏工具：读取 MacBook 内屏当前
亮度，并通过 DDC/CI 让外接显示器跟随。系统自动亮度和键盘手动调节都会同步。

## 功能

- 直接同步 MacBook 内屏当前亮度，而不是只同步亮度变化量。
- 可设置外屏亮度比例和最低亮度，修正不同面板的观感差异。
- 苹果键盘亮度键按鼠标所在屏幕分流：
  - 鼠标在内屏时，由 macOS 调整内屏，外屏随后跟随。
  - 鼠标在支持 DDC 的外屏时，直接调整该外屏。
- `Option + Shift` 保留 macOS 风格的四分之一档细调。
- 定时从 DDC 回读真实亮度；如果显示器自动亮度、DDPM 或其他工具覆盖写入，
  界面不会继续显示缓存出来的“同步成功”。
- 合盖时可以启用实验性的 Dell 自动亮度补偿和最低亮度保护。

## 兼容性与验证状态

- Apple Silicon Mac。
- macOS 13 或更高版本。
- 支持 DDC/CI 亮度控制的外接显示器。
- 已在 Dell U2725QE 通过 USB4 完成 DDC 读取、写入和回读验证。
- 原生 HDMI 使用同一套 DDC 检测与读写路径，但尚未在本项目中完成等价实测。
- 其他品牌和型号可能可用，但尚未建立兼容性列表。

本项目使用 macOS 私有的 DisplayServices 与 IOAVService 接口，不能提交 Mac
App Store；系统大版本升级后也可能需要适配。

## 使用前

1. 在显示器菜单中开启 DDC/CI。
2. 开盖跟随 MacBook 时，关闭显示器自带自动亮度。
3. 合盖使用 Dell 自动亮度增强时，保持 Dell 自动亮度开启。
4. 退出 DDPM、BetterDisplay、MonitorControl 等其他亮度控制工具，避免互相覆盖。
5. 首次启动后，在“系统设置 → 隐私与安全性 → 辅助功能”中允许本工具，
   以便拦截并按鼠标位置分流亮度键。

## 构建

先运行测试：

```sh
swift test --disable-sandbox
```

仅在本机自用时，可以创建一张固定的本地代码签名身份，然后打包：

```sh
./Scripts/create-local-signing-identity.sh
./Scripts/build-app.sh "$PWD/BrightnessFollow.app"
open "$PWD/BrightnessFollow.app"
```

`create-local-signing-identity.sh` 会在登录钥匙串中创建一张有效期十年、仅用于
代码签名的自签证书。私钥保留在钥匙串，不会写进项目。固定签名身份可以防止
每次重新构建后 macOS 都把应用视为新程序并重新要求辅助功能授权。

请只在理解这项系统信任变更后运行该脚本，不要导出或分享生成的私钥。如果已
拥有 Apple Development 或 Developer ID 证书，可以直接指定现有身份：

```sh
BRIGHTNESS_FOLLOW_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./Scripts/build-app.sh "$PWD/BrightnessFollow.app"
```

构建脚本在找不到稳定签名身份时会停止，不会回退到容易导致权限失效的 ad-hoc
签名。后续部署时请保持 Bundle ID 和应用路径不变。

## 诊断

```sh
swift run --disable-sandbox BrightnessFollow --probe
swift run --disable-sandbox BrightnessFollow --verify-ddc
```

`--probe` 只读取显示器状态。`--verify-ddc` 会把当前外屏亮度原值写回并再次
读取验证，不改变最终亮度。

## 隐私

应用不包含网络请求、账号系统或遥测。亮度配置保存在本机。

## 开源许可

项目使用 [MIT License](LICENSE)。Apple Silicon DDC 传输实现参考了
[MonitorControl](https://github.com/MonitorControl/MonitorControl)，详见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和
[MONITORCONTROL_LICENSE.txt](MONITORCONTROL_LICENSE.txt)。
