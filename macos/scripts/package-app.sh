#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
./scripts/build-app.sh
./scripts/build-demo-app.sh
architecture="$(uname -m)"
build_root="$project_dir/dist/apps.noindex"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
image_path="$project_dir/dist/Keynest-$version-$architecture.dmg"
stage_dir="$(mktemp -d "$build_root/.installer.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
ditto "$build_root/Keynest.app" "$stage_dir/Keynest.app"
ditto "$build_root/Keynest Demo.app" "$stage_dir/Keynest Demo.app"
cp "$project_dir/../LICENSE" "$stage_dir/LICENSE"
cp "$project_dir/../THIRD_PARTY_NOTICES.md" "$stage_dir/THIRD_PARTY_NOTICES.md"
cat > "$stage_dir/安装说明.txt" <<'TEXT'
Keynest 0.11.0 — 本地 API、Skill 与 Agent 凭据收藏

统一安装到个人的 ~/Applications 文件夹，不要直接从镜像运行。
在 Finder 中选择「前往文件夹…」，输入 ~/Applications，再复制两个 App。
从源码安装时，推荐运行 scripts/install-apps.sh；它会先校验并压缩备份旧版本。
首次打开时，请自行设置至少 12 个字符的主密码。主密码无法找回。
支持 Touch ID 的 Mac 可在解锁时勾选启用，或在设置中开启；以后打开时使用系统指纹验证。
主密码始终保留为备用。指纹配置变化或更换主密码后，需要用主密码解锁并重新启用。
密钥和备注保存在本机加密文件中；建议定期导出 .keynest 加密备份。
解锁后进入首页：按平台直接复制密钥，选平台并粘贴即可快速添加。
同一平台的多把密钥分别展示，账号、环境与地址帮助区分；完整编辑在更多菜单中。
点击钥匙串挂件直接复制已选密钥；同平台多把密钥时，先在「定制」中选择。
原绑定密钥已失效时需重新选择，不会自动换成另一把。没有密钥的平台可快速添加。
「编辑布局」可原地拖动平台卡片，支持保存、取消与恢复默认；布局随密钥库加密保存。
首次保存旧格式前保留 vault-before-0.11.keynest 升级备份；旧备份不覆盖。

Keynest Demo.app 是独立演示版，测试密码：Keynest-Demo-2026。
演示版只有虚构样例，与正式密钥库分开；不要存放真实凭据。
可以体验搜索、添加、编辑、显示和复制；不发送额度请求，不导入导出备份。

最低 macOS 14。此包按构建机器的处理器架构生成。
这是本机编译、临时签名的实验版，未获 Apple 公证，也未经独立安全审计。
没有云同步、遥测或账户。额度查询需手动开启并点击，只访问所选平台官方接口。
TEXT
cat > "$stage_dir/INSTALL.txt" <<'TEXT'
Keynest 0.11.0 — local API, Skill and Agent credential manager

Requires macOS 14+ on the processor architecture named in the DMG filename.
Copy Keynest.app and, optionally, Keynest Demo.app to ~/Applications.
Open the installed copy, not the app inside this disk image.
The app interface is currently Chinese. English documentation:
https://github.com/kody1126/Keynest/blob/main/README.en.md

Create a master password on first launch. There is no password recovery.
Touch ID is optional; the master password remains available as a fallback.
Export encrypted .keynest backups regularly and keep the password safely.
Click a keyring charm to copy its selected key; choose one in Customize when a
provider has several keys. A missing selected key never falls back to another.
Edit Layout lets you drag Home cards, save or cancel, and restore the default.
Layout and charm bindings are encrypted with your vault and backups.
Before upgrading an older vault, vault-before-0.11.keynest preserves its bytes.
The separate demo vault uses the public password: Keynest-Demo-2026
Demo credentials are fictional. Never put real credentials in the demo.

Experimental local build with ad-hoc signing and Hardened Runtime.
Not Developer ID signed, not Apple notarized, not independently audited.
No cloud account, telemetry or automatic cloud synchronization.
Quota requests are opt-in and manual, to fixed official provider endpoints.

Original code: MIT (see LICENSE).
Brand artwork is separately licensed or subject to vendor terms; see
THIRD_PARTY_NOTICES.md and source/license records bundled inside each app's
Contents/Resources/ProviderIcons and Contents/Resources/ToolIcons directories.
TEXT
if [[ -L "$image_path" || -L "$image_path.sha256" ]]; then
    print -u2 "Refusing a symbolic-link package destination."
    exit 1
fi
hdiutil create -volname Keynest -srcfolder "$stage_dir" -ov -format UDZO "$image_path"
hdiutil verify "$image_path"
(cd "${image_path:h}" && shasum -a 256 "${image_path:t}") > "$image_path.sha256"
print "Packaged: $image_path"
