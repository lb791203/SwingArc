# SwingArc 1.0 App Store 提交清单

## 已在仓库准备

- [x] iPhone App 图标：1024 × 1024、无透明通道，含默认/深色/着色版本。
- [x] 品牌启动页。
- [x] `PrivacyInfo.xcprivacy`：不跟踪、不收集数据；声明 `UserDefaults` 与系统启动时间的批准用途。
- [x] 隐私政策页面（中英双语）。
- [x] 支持页面（中英双语、公开联系邮箱）。
- [x] 简体中文商店名称、副标题、宣传文本、描述、关键词、类别和首发说明。
- [x] App Review 审核路径与隐私说明。
- [x] 相机、照片读取和照片写入用途文案。
- [x] 移除过时的麦克风权限声明。
- [x] 声明不使用非豁免加密。
- [x] 首发设备范围设为仅 iPhone。
- [x] 工程纳入仓库，可从克隆目录直接构建和归档。
- [x] TestFlight 配置：支持 Xcode 直接上传或导出 IPA 后使用 Transporter 上传；均不自动提交 App Store 审核。

## App Store Connect 必须由账号持有人确认

- [ ] Apple Developer Program 会员有效；最新协议已接受。
- [ ] 新建 App 记录：名称 `SwingArc`、Bundle ID `com.liangbo.swingarc`、版本 `1.0`、SKU 自定义且唯一。
- [ ] 确认 App Store 上的名称可用；若重名，先确定新名称再上传首个构建。
- [ ] 主语言选择简体中文，主类别选择“体育”，次类别建议“照片与视频”。
- [ ] 填写 App Review 联系人姓名、`liang.ctp@gmail.com` 和可接听电话（电话仍待提供）。
- [ ] 隐私问卷选择“不从此 App 收集数据”。
- [ ] 完成 2026 年新版年龄分级问卷。
- [ ] 确认第三方内容权利声明。
- [ ] 选择价格与销售地区；首发建议免费。
- [ ] 如在欧盟上架，完成并验证 DSA trader / non-trader 状态。
- [ ] 中国大陆上架前核对当地备案要求；没有所需资料时先不选择中国大陆。
- [ ] 选择手动发布，待审核通过后再由开发者控制上线时间。

## 构建与审核前验证

- [ ] 冻结首发源代码；当前未提交的 P1–P8/回放实验必须先独立收口或排除。
- [ ] 在支持的最低系统 iOS 17 真机验证首次安装、权限拒绝/重新授权和低存储空间路径。
- [ ] 真机验证 DTL、FACE-ON、手动录像、相册导入、AI 分析、回放、画线、导出、项目重开和删除。
- [ ] 验证无麦克风权限弹窗、无网络请求、无崩溃。
- [ ] 运行 Release archive、`Validate App`，并导出 App Store Connect 包。
- [ ] 使用 `ExportOptions-TestFlight.plist` 直接上传，或使用 `ExportOptions-Transporter.plist` 导出 IPA 后通过 Transporter 上传。
- [ ] 等待 Apple 处理完成并检查所有警告。
- [ ] 用 TestFlight 构建再做一次真机冒烟测试。

## 截图

- [ ] 至少上传 1 张、最多 10 张 iPhone 截图；建议 5 张。
- [ ] 使用 6.9 英寸支持尺寸（建议 1320 × 2868 竖屏），PNG/JPEG 且无透明通道。
- [ ] 建议内容：四入口主页、视觉自动练习、手动录像、P1–P8 慢动作分析、画线与技术反馈。
- [ ] 截图必须显示真实 App 画面，不展示测试数据、个人通知或调试 UI。

## 发布资料 URL

- 隐私政策：`https://lb791203.github.io/SwingArc/app-store/privacy/`
- 支持：`https://lb791203.github.io/SwingArc/app-store/support/`

上述 URL 需在发布分支合并到 `main` 并启用 GitHub Pages（`main` / `/docs`）后再次打开验证。
