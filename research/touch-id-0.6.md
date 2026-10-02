# Keynest 0.6 Touch ID 后端

验证日期：2026-09-29。实现位于 `macos/Sources/KeynestApp/BiometricVaultAccess.swift`；密码加密格式保持兼容。

## 选择与本机证据

最初方案是将派生会话密钥放入 Data Protection Keychain，使用 `.biometryCurrentSet` 与 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。Apple 说明 macOS 的 Data Protection Keychain 按代码签名 entitlement 的 access group 授权，需要相应 provisioning profile。`kSecUseDataProtectionKeychain` 选择该实现，而不是传统文件钥匙串。[TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)、[Data Protection Keychain 开关](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain)

本机只读检查：`security find-identity -v -p codesigning` 返回 `0 valid identities found`；当前已安装 Keynest 是 arm64 ad-hoc 签名，未设置 TeamIdentifier。使用单独编译、明确 ad-hoc 签名的临时程序进行无交互探测，结果如下：

| 探测 | 结果 |
| --- | --- |
| `SecureEnclave.isAvailable` | `true` |
| `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` | `true` |
| 随机独立 service/account 的 DP Keychain metadata 查询 | `-25300`，item not found |
| 仅含虚构数据且带 biometric ACL 的 DP Keychain `SecItemAdd` | `-34018`，missing entitlement |
| 对同一独立标识执行清理删除 | `-34018`；添加未成功，没有遗留条目 |
| CryptoKit 非永久 Secure Enclave 私钥创建，current-set biometric ACL | 成功 |
| 私钥 ECDH，fresh LAContext、`interactionNotAllowed = true` | 拒绝，`com.apple.LocalAuthentication -1004` |

因此不能根据 metadata 查询的 item-not-found 结果宣称 DP Keychain 可写；本版也未生成证书、伪造 entitlement 或退回 legacy Keychain。采用硬件私钥操作受系统生物识别约束的 CryptoKit Secure Enclave 方案。Apple 提供带 access control / authentication context 的非永久密钥初始化与 dataRepresentation 重建接口。[Secure Enclave 密钥协商](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement)、[带 ACL 的私钥初始化](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/keyagreement/privatekey/init(compactrepresentable:accesscontrol:authenticationcontext:))

## 保存与解锁流程

1. 用户用主密码解锁后明确启用 Touch ID；Core 将当前派生会话密钥编码为小型 token。它包含版本标识、保险库格式摘要、32 字节随机 vault salt 和 32 字节派生密钥，不包含主密码或凭据正文。
2. 创建 Secure Enclave P-256 key-agreement 私钥，ACL 使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`、`.biometryCurrentSet`、`.privateKeyUsage`，没有 `.userPresence`、`.devicePasscode` 或 `.or` 放宽。
3. 新建仅存在于内存的临时软件 P-256 peer，用 peer 私钥与 enclave 公钥做 ECDH；HKDF-SHA256 导出 256-bit wrapping key，AES-GCM 加密 token。登记使用公钥一侧的运算，无需弹出指纹提示。
4. 保存 enclave opaque `dataRepresentation`、peer 公钥、随机 HKDF salt 和 AES-GCM 密文。Apple 明确说明 Secure Enclave 导出的表示是加密块，只有原 Secure Enclave 能还原，不是原始私钥。[Apple CryptoKit 密钥存储说明](https://developer.apple.com/documentation/cryptokit/storing-cryptokit-keys-in-the-keychain)
5. 真正解锁时重新构建 enclave 私钥，执行私钥 ECDH；该系统操作必须满足 ACL，成功后才能导出 wrapping key 和解密 token。再由 Core 验证 token 的 salt/格式与保险库一致，并验证保险库 AES-GCM tag。不是先用 `evaluatePolicy` 显示一个 UI，再读取未受保护的密钥。

每次操作新建 LAContext；每次解锁 `touchIDAuthenticationAllowableReuseDuration = 0`；结束或取消后 invalidate。没有先认证再复用的 context。Apple 说明 duration 为零时不复用设备刚解锁的 Touch ID；已认证 context 本身也不可在后续解锁间复用。[复用时长](https://developer.apple.com/documentation/localauthentication/lacontext/touchidauthenticationallowablereuseduration)、[认证 context 语义](https://developer.apple.com/documentation/security/ksecuseauthenticationcontext)

指纹集合改变会使 `.biometryCurrentSet` 保护失效。用户仍可使用主密码，再重新启用 Touch ID。[Apple 当前指纹集合 ACL](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/biometrycurrentset)

## 本地文件与并发

- sidecar 为保险库同目录的 `biometric-unlock.keynestlocal`；不进入密码加密备份，不保存到 UserDefaults，不发往网络。
- 目录必须属于当前用户、权限不对 group/other 开放；新文件权限 `0600`。使用目录 fd 和 `openat` / `O_NOFOLLOW`；只接受 regular、当前用户所有、single-link 文件；拒绝符号链接与硬链接。
- 读取上限 16 KiB。写入独立 `O_EXCL` 临时文件，`fsync` 后同目录原子 `renameat`；失败清理临时文件。
- vault 文件规范化路径的 SHA-256 同时进入记录、HKDF context 和 AEAD AAD；另一个 profile 的 sidecar 不能直接借用。token 内的 vault salt 进一步阻止别的库或新主密码派生会话使用旧 token。
- 所有文件与加密操作在专用串行后台队列；主线程不等待指纹验证。epoch 与活跃 LAContext 由 NSLock 保护。取消会提高 epoch 并 invalidate context。
- 登记/撤销的 epoch 检查与磁盘提交在同一锁内。取消先发生则不提交；提交先完成则视为已完成操作，不会在文件已提交后再误报为取消。AppModel 仍负责用自身 lock epoch 防止迟到结果解锁界面。
- 状态读取禁止交互，不解密 token、不执行私钥 ECDH；格式或 opaque key 失效返回未登记，允许主密码解锁后重新登记。撤销在文件不存在时幂等，在异常文件/权限错误时失败关闭。

## 已执行检查

- `BiometricTokenTests.swift` 独立执行：**7 tests，272 assertions，0 failures**。包括 round-trip、继续保存后密码可解锁、每个 token 字节翻转、所有截短长度、额外字节、别的库、换主密码、正确 salt 配错误密钥、篡改密文/格式、原文件保留。
- `BiometricVaultAccess.swift` 通过 Swift 5、macOS 14 target、`-strict-concurrency=complete` 独立 typecheck。
- 编译 ad-hoc 签名的真实后端临时程序：**12 assertions 全通过**。覆盖无提示登记、只读状态、文件 `0600`、无 token 明文、跨 profile 拒绝、损坏 opaque 可重新登记、删除/重复删除、拒绝符号链接且目标未变。直接用持久化 opaque 数据重建私钥后，在禁止 UI 的全新 context 中执行 ECDH，系统以 `LA -1004` 拒绝。
- 同样的检查已保留为 `bash macos/scripts/run-biometric-checks.sh` 与 `macos/scripts/BiometricChecks.swift`，以便在登录用户的正常桌面会话重现；受限制执行沙箱可能屏蔽系统安全服务，脚本会真实失败而不会伪报通过。
- 上述运行全部使用 `/private/tmp/keynest-biometric-*` 的虚构数据，服务测试目录退出时清理；没有调用生产 `unlockData()`、没有弹出生物识别 UI、没有操作用户真实密钥库。
- 全量 Core suite 的首次启动在编译阶段发现新测试对 `VaultDocument` 错用 Equatable；已改为比较 entries/tools/version。因本轮 provider catalog 正并行修改，随后只隔离执行上述 7 个新测试；最终全量集成由主任务统一执行。

## 仍需区分的安全边界

安装后的 0.6 演示版已实测启用、锁定并点击 Touch ID：受保护私钥操作成功，界面约 4 秒后恢复 24 条记录，过程中自动化没有输入主密码。已经向用户请求确认是否看到系统提示并实际按了指纹，物理操作确认尚待回复；没有在真实系统上删除/新增指纹测试失效。应区分“受保护操作与应用解锁链路成功”和“用户明确确认实际指纹操作”，不把自动化观察写成后者。

这个 sidecar 方案没有 DP Keychain 的应用 access-group 身份隔离。具有同一用户文件读取权限的其他程序可能复制 opaque blob 并尝试请求自己的系统生物识别授权；它不能从文件直接取得私钥或派生 vault key。保持 `0600`、不共享文件、只接受预期应用发起的认证仍有意义。将来具备正式签名/provisioning 后，可另行采用 DP Keychain 增强应用身份隔离；不能把当前方案宣称为完全等价的 Keychain access-group 保护。

删除 sidecar 撤销的是当前本地登记，不保证销毁已被外部复制的旧加密记录；更改主密码产生新 vault salt 后，旧 token 无法解锁新库。复制旧保险库与旧登记的历史快照需要按其原有保护处理。解锁后派生密钥必须在进程内用于解密，Swift 的 Data 值复制也不能承诺所有临时内存立即归零。

系统主密码回退仍是 Keynest 自己的主密码输入流程；本版没有将系统登录密码作为 biometric ACL 的替代凭据。加密备份的密码恢复能力不依赖这台设备、其 Touch ID 或 sidecar。
