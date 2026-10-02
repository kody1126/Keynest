# 原生 macOS Keynest 接口契约

此文档保留早期接口草案；完整现行功能与安全边界以 [README](README.md) 和 [0.8.1 检查报告](../research/security-review-0.8.1.md) 为准。

目标：纯 SwiftUI/AppKit + CryptoKit + CommonCrypto，macOS14+，无需 Node/浏览器/联网安装依赖。根目录 .data 不动。用户正式数据 ~/Library/Application Support/Keynest/vault.keynest。测试数据隔离。

## Core 库（storage agent owns all KeynestCore except QuotaClient.swift）

public enum EntryCategory: String, Codable, CaseIterable, Sendable: ai, skill, service, other。public var title:String, symbol:String。
public enum QuotaProvider: String, Codable, CaseIterable, Sendable: none, deepseek, siliconflow, openrouter。public var title:String, endpoint:URL?。
public struct SecretEntry: Identifiable,Codable,Equatable,Sendable。public vars:
 id:UUID, name:String, category:EntryCategory, provider:String（任意供应商名）, secret:String, baseURL:String, website:String（控制台/来源）, tags:[String], notes:String, isFavorite:Bool, quotaProvider:QuotaProvider, quota:QuotaSnapshot?, createdAt:Date, updatedAt:Date。
 public init(id:UUID=UUID(),name:String="",category:EntryCategory=.ai,provider:String="",secret:String="",baseURL:String="",website:String="",tags:[String]=[],notes:String="",isFavorite:Bool=false,quotaProvider:QuotaProvider=.none,quota:QuotaSnapshot?=nil,createdAt:Date=Date(),updatedAt:Date=Date())
 public func validated() throws -> SecretEntry （验证名称非空<=120，secret非空<=8192且无CR/LF/NUL，标签数量<=12，各<=40；notes<=4000；URL http(s)，不含userinfo/query/hash。provider<=120 任意来源）
public struct QuotaMetric: Codable,Equatable,Sendable {public var label:String,value:String?,currency:String?;public init(label:String,value:String?,currency:String?=nil)}
public struct QuotaSnapshot: Codable,Equatable,Sendable {public var kind:String,metrics:[QuotaMetric],note:String,fetchedAt:Date;public init(kind:String,metrics:[QuotaMetric],note:String="",fetchedAt:Date=Date())}
public struct VaultDocument:Codable,Sendable {public var version:Int=1,entries:[SecretEntry]; public init(entries:[SecretEntry]=[])}
public struct VaultSession:Sendable（key和salt内部即可）
public enum VaultCodec:
 static func createSession(password:String) throws -> VaultSession
 static func encrypt(_ document:VaultDocument,session:VaultSession) throws -> Data
 static func decrypt(_ data:Data,password:String) throws -> (document:VaultDocument,session:VaultSession)
 static func validatePassword(_ password:String) throws
 AES-GCM + PBKDF2-SHA256 600000 iterations(CommonCrypto)，salt32/nonce随机，format+KDF params认证，严格schema，4MiB限制，密码12..1024；新密码 UTF-8 最多16KiB，旧密码解锁兼容。
public struct VaultStorage:Sendable:
 public let directory:URL, fileURL:URL
 public init(directory:URL) throws （mkdir0700拒绝symlink）
 public var exists:Bool
 public func read() throws -> Data
 @discardableResult public func write(_ data:Data) throws -> VaultWriteResult （0600原子写入，无明文临时文件；返回 durable 或 durabilityUncertain，后者表示替换已完成但目录同步未确认）
错误用LocalizedError中文。
Core tests验证加解密/重开/篡改/错误密码/无明文/字段验证/权限。

## AppModel（root owns AppModel.swift 和 KeynestApp.swift）
@MainActor final class AppModel:ObservableObject。可供Views使用:
 @Published var entries:[SecretEntry]=[], isLocked=true, isInitialized=false, busy=false, errorMessage:String?, toast:String?, selectedID:UUID?, searchText="", filter:LibraryFilter=.all, presentingEditor=false, editingEntry:SecretEntry?, syncInProgress:Set<UUID>=[], syncErrors:[UUID:String]=[:]
 enum LibraryFilter: Hashable {case all,favorites,category(EntryCategory)}
 var filteredEntries:[SecretEntry]; var selectedEntry:SecretEntry?; var dataPath:String
 func unlock(password:String) async; func create(password:String) async; func lock(); func activity();
 func addNew(category:EntryCategory?=nil); func edit(_ entry:SecretEntry); func save(_ entry:SecretEntry) throws; func delete(_ entry:SecretEntry) throws; func toggleFavorite(_ entry:SecretEntry); func copySecret(_ entry:SecretEntry); func syncQuota(_ entry:SecretEntry) async;
 func exportBackup(); func importBackup()（NSOpenPanel启动后弹restore密码由root另写RestoreSheet，Views不用）；func changePassword()（root处理sheet）
锁屏、10min闲置/系统睡眠/退出清内存；闲置使用单调时钟；剪贴板 currentHostOnly，30sec清除仅 prepareForNewContents 返回的归属计数仍匹配；自动lock不让网络查询延长。

## Views（UI agent owns Views.swift, EntryEditor.swift）
struct MainView:View 使用 @EnvironmentObject var model:AppModel。
原生NavigationSplitView sidebar（全部、收藏、AI模型、Skill与插件、开发服务、其他）+中列列表+详细页；native toolbar新增、搜索、锁定；.searchable 或原生搜索框。中文、SF symbols、系统字体、灰阶＋少量蓝绿accent，适配深色，native sheet编辑；不要网页hero、大量统计卡或花哨阴影。显示账户/提供商文字和用途重点“收藏”。
锁屏 setup/unlock view own 用model.isInitialized，不做TouchID假按钮；password确认及12字符说明。详情默认mask，点击显示20秒，选择变化/锁定/失焦清除。copy用model方法。原生按钮打开控制台链接（NSWorkspace?处理http(s)），展示secret来源、环境tag、备注；favorite、编辑、删除确认。
struct EntryEditor:View 接受 entry:SecretEntry,onSave:(SecretEntry)throws->Void（保存失败显示本地错误），onCancel:()->Void。编辑现有 secret预填SecureField（仅解锁内存），不要无限次放入Text/调试日志；更改任何认证相关字段后清quota。advanced DisclosureGroup quotaProvider选择，默认none；备注和分类以任意Skill key为重点。
合适的empty state, Cmd+N、Cmd+F、Cmd+Shift+L由root commands提供，copy快捷Cmd+Shift+C。所有数据为原生Text无需html。
