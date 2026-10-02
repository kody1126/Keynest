# Keynest 0.8.1 安全检查与修复

检查日期：2026-10-02 至 2026-10-03。范围包括原生 macOS App、加密与文件存储、Touch ID 边界、导入/改密码、剪贴板、额度请求，以及根目录保留的 0.1 Web 实验。方法是源码检查、可复现回归、故障注入、隔离虚构库测试和安装后的 Demo 交互检查；不是第三方独立安全审计或渗透测试认证。

## 结论与加密方式

本项目没有使用 MD5。MD5 是摘要算法，不是可逆加密；它不适合保存密码，也不能替代下面的加密和密码派生机制。

| 用途 | 实际实现 |
| --- | --- |
| 原生密钥库与导出备份 | Apple CryptoKit AES-256-GCM，256 位密钥、每次写入随机 12 字节 nonce、16 字节认证 tag；格式与 KDF 参数经过 AAD 认证 |
| 原生主密码派生 | CommonCrypto PBKDF2-HMAC-SHA256，600,000 次迭代，32 字节随机 salt，派生 32 字节密钥 |
| 安全随机数 | Security 的 SecRandomCopyBytes；失败时中止，不用普通伪随机代替 |
| Touch ID | Secure Enclave P-256 私钥，当前指纹集合及私钥运算访问控制；ECDH / HKDF-SHA256 派生包装密钥，AES-GCM 包装解锁资料；绑定当前库路径，不保存主密码明文 |
| 早期 Web 实验 | Node 内置 crypto，AES-256-GCM + scrypt（N=131072、r=8、p=1、32 字节 salt）；与原生文件格式不互通 |
| 安装包校验 | SHA-256；用于检查文件一致性，不能替代可信发布者签名 |

整库加密包括平台、名称、密钥、账号、环境、标签、备注、工具关系和额度快照。应用不主动上传密钥库，不扫描其他工具的凭据。只有用户明确选择的额度查询才发送该把密钥到固定官方 HTTPS 接口；点击官网会打开默认浏览器。

PBKDF2 参数符合 OWASP 针对 PBKDF2-HMAC-SHA256 给出的 600,000 次要求。OWASP 同时优先推荐 Argon2id；本次保持系统库实现和旧库兼容，没有无迁移方案地更换 KDF。这不意味着主密码强度可以忽略。

## 原生 App 已修复问题

| 问题与影响 | 修复及回归 |
| --- | --- |
| 点击取消导入后，尚未完成的解密仍可能继续合并或创建库 | 导入有独立任务代次，取消/锁定使旧结果失效；成功提交后立即关闭取消窗口。测试取消期间原密文与条目不变，并验证正常导入仍成功 |
| 改密码异步提交时仍可关闭表单，容易误以为操作已取消 | 提交期间禁用取消及交互关闭；退出表单释放密码字段；异步错误遵守会话代次 |
| 复制没有明确禁止跨设备接力，归属竞争可能误清其他软件的新内容 | 发布时使用 currentHostOnly，敏感/临时标记与字符串一次写入；记录 prepareForNewContents 返回的归属计数，只清自己的复制；写入失败不显示成功 |
| 系统时间回拨可能延长闲置解锁时长 | 闲置计时改用 systemUptime 单调时钟，数据时间戳仍使用日历时间；覆盖到期前后及锁定后复制拒绝 |
| 库文件或升级备份为硬链接时，收紧权限可能影响链接到的其他文件 | 在读取、chmod 和替换前检查普通文件及单一链接；单实例锁同时核验所有者；测试拒绝硬链接且外部文件权限不变 |
| 原子替换已完成，但目录 fsync 失败后 App 保留旧内存/旧会话 | 写入结果区分 durable 与 durabilityUncertain；两者均按已提交更新内存和密码会话，后者提示导出备份；故障注入覆盖 EIO/EINVAL/ENOTSUP 及改密码 |
| 带非零起始索引的 Data 切片作为指纹解锁资料时可能崩溃 | token 字段偏移相对 startIndex；回归合法切片与错误资料 |
| URL 控制字符/非法端口可能被系统解析为与原字符串不同的地址 | 新输入拒绝控制字符和不在 1–65535 内的端口；旧库元数据兼容读取，非法地址禁止外部使用并可编辑修正；密钥正文保持原样 |
| 按字符数限制的新密码仍可能包含异常多的 UTF-8 字节 | 新建及改密码额外限制为 16 KiB，KDF 借用连续 UTF-8 字节而非额外数组；旧密码仍按旧规则解锁，避免锁死旧库 |
| 关闭编辑窗口后模型仍持有草稿引用 | 取消及退出窗口清理编辑条目引用；不宣称 Swift 所有内存副本已物理清零 |
| 本机构建缺少 Hardened Runtime | 两个构建脚本均启用运行时保护；最终签名 flags=0x10002(adhoc,runtime)，未加入放宽保护的 entitlement |

## Web 实验已修复问题

根目录 Web 是独立的早期实验，不随原生 App 启动或打包为运行依赖。

- 显示密钥请求晚于 Escape 或窗口失焦返回时，会重新显示明文：增加显示代次，过期响应丢弃。
- pagehide 后 DOM、草稿及未完成解锁清理不完整：清理页面状态，使异步结果失效，并尽力发送锁定请求。页面退出请求仍受浏览器生命周期限制，不能保证网络投递成功。
- 已认证解密的 JSON 仍可能含非法时间、额度结构或未知字段：严格校验载荷，并对白名单公开字段投影，避免直接向浏览器扩散未来新增的敏感字段。
- 库文件读取的路径检查与使用分离，硬链接可能连带 chmod，运行中替换为 FIFO 也可能阻塞：通过 O_NOFOLLOW / O_NONBLOCK 打开 FD，fstat 核验普通文件、链接数、所有者和大小，再 fchmod 与限量读取；初始化、解锁和备份使用同一路径。
- 闲置与重试退避依赖系统日历时间：改为 performance.now 单调时间；浏览器活动 ping 同步调整，数据时间戳仍使用日历时间。
- 新 API URL 拒绝控制字符；兼容规范旧库中此前接受的控制字符 URL，保留密钥和元数据。旧 URL 编码扩张的兼容边界通过旧加密文件回归验证。

## 验证与安装

- 原生核心：167 项测试、7423 条断言全部通过；故意失败断言自检通过，避免无效运行器“假通过”。
- AppModel：121 条隔离检查通过。使用虚构库、模拟指纹、模拟剪贴板和注入时钟/磁盘失败，不读取真实凭据。
- Touch ID 文件保护：`run-biometric-checks.sh --file-only` 的 15 条检查通过；不查询传感器、不创建 Secure Enclave 密钥，也不执行真实指纹验证。
- Clipboard 归属语义另用唯一命名的临时 pasteboard 验证：prepare 返回的计数代表归属，writeObjects 不增加该计数；其他写入会改变归属。没有用用户常规剪贴板做该探针。
- 最终 release 构建和两个 App 的严格签名验证通过；DMG 校验和 SHA-256 通过。已安装到原来的 `~/Applications`，均为 0.8.1（build 9），可执行文件、Info.plist 和 App 图标与打包产物一致。
- 已安装 Demo 能用原公开密码打开，首页保留 31 个平台、34 把虚构密钥；复制开发样例与预期一致，30 秒后再粘贴为空，锁定后条目与详情全部收起。
- 正式库、指纹封装和旧升级备份的存在性/密文元数据与检查前一致；本轮未创建正式库，未改写真实密钥或调用真实服务 API。
- Web 最终 `npm test` 的 50 项测试全部通过，包含实际 app.js 在 VM/最小 DOM 下的异步状态回归；未重新执行完整浏览器手工验收。详见 [Web 验证记录](VERIFICATION.md)，与原生计数分开。

数据载荷仍为版本 3，加密外层仍为版本 1，Demo 目录修订仍为 7。C2 图标及全部 12 个候选、61 个 API 和 15 个工具品牌图标保留。未要求用户重新录入已有凭据。

## 仍然存在的安全边界

1. 不能保证绝对安全。本次是开发方检查，没有独立第三方审计；macOS 14 最低系统和 Intel 设备未在本轮实机覆盖。
2. 静态加密主要保护锁定状态的磁盘与备份。弱主密码仍可能遭离线猜测；同用户恶意软件、管理员/root 权限、本机已受控、解锁中的内存读取或屏幕捕获超出这一保护范围。
3. 锁定会释放应用的会话/数据引用并清理可控缓冲区，但 Swift 字符串、系统组件或其他副本不保证物理清零。
4. currentHostOnly 是明确的本机复制策略；第三方剪贴板软件可忽略敏感标记。未做两台物理设备的接力测试。用户后续粘贴到网站或软件，是新的数据传递行为。
5. 本轮文件防护也不构成对同 UID 恶意进程并发操纵路径祖先的隔离保证。Hardened Runtime 已启用，但应用仍采用本地 ad-hoc 签名，没有 App Sandbox、Developer ID 签名或 Apple 公证；它不能阻止当前用户主动替换/重新签名程序。
6. 本轮保留原 Touch ID 设计，验证文件防护和模拟成功/失败/取消状态，没有重新执行物理指纹成功解锁。Secure Enclave 的原始验证范围见 [0.6 记录](touch-id-0.6.md)。
7. 删除本地收藏不等于撤销服务商 API Key。升级前加密备份仍使用原密码；改密码不会追溯重加密外部备份。
8. 磁盘故障通过注入模拟，未进行真实掉电测试。旧 Web 实验的文件持久化和浏览器剪贴板能力与原生 App 不等同；推荐使用原生 App。

## 官方依据

- [OWASP 密码存储建议](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)：密码 KDF、PBKDF2 参数及 MD5 等旧算法的限制。
- [OWASP 加密存储建议](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)：认证加密与 AES。
- [Apple CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)：本项目使用的认证加密实现。
- [Apple NSPasteboard currentHostOnly](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly)：禁止该次剪贴板内容在其他设备使用。
- [Apple Secure Enclave](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave)：硬件保护的私钥操作。
- [Apple Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)：运行时保护的作用及配置。
