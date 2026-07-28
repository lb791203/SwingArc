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
- [x] 首发范围：手动录像、视频导入、回放、P1–P8、人工修正、画线、记录和导出。
- [x] 价格：免费；无内购、订阅或付费墙。

## App Store Connect 必须由账号持有人确认

- [ ] Apple Developer Program 会员有效；最新协议已接受。
- [ ] 新建 App 记录：名称 `SwingArc`、Bundle ID `com.liangbo.swingarc`、版本 `1.0`、SKU 自定义且唯一。
- [ ] 确认 App Store 上的名称可用；若重名，先确定新名称再上传首个构建。
- [ ] 主语言选择简体中文，主类别选择“体育”，次类别建议“照片与视频”。
- [ ] 填写 App Review 联系人姓名、`liang.ctp@gmail.com` 和可接听电话（电话仍待提供）。
- [ ] 隐私问卷选择“不从此 App 收集数据”。
- [ ] 完成 2026 年新版年龄分级问卷。
- [ ] 确认第三方内容权利声明。
- [ ] 选择销售地区；中国大陆暂不启用，其他地区按发行意图选择。
- [ ] 欧盟销售范围启用前，账号持有人已完成真实的 DSA trader / non-trader 声明。
- [ ] 中国大陆暂不启用：尚无有效 ICP 备案号；取得备案并核对简体中文元数据后再开放。
- [ ] 选择手动发布，待审核通过后再由开发者控制上线时间。

## 构建与审核前验证

- [ ] 使用公开版、App Store 支持的 Xcode 和 iOS 26 SDK 或更高版本归档。
- [ ] 在支持的最低系统 iOS 17 真机验证首次安装、权限拒绝/重新授权和低存储空间路径。
- [ ] 真机验证手动录像、相册导入、P1–P8、人工修正、回放、画线、导出、项目重开和删除。
- [ ] 验证无麦克风权限弹窗、无网络请求、无崩溃。
- [ ] 运行 Release archive、`Validate App`，并导出 App Store Connect 包。
- [ ] 使用 `ExportOptions-TestFlight.plist` 直接上传，或使用 `ExportOptions-Transporter.plist` 导出 IPA 后通过 Transporter 上传。
- [ ] 等待 Apple 处理完成并检查所有警告。
- [ ] TestFlight 处理后的同一构建已完成真机全流程验收。

## 截图

- [ ] 至少上传 1 张、最多 10 张 iPhone 截图；建议 5 张。
- [ ] 使用 6.9 英寸支持尺寸（建议 1320 × 2868 竖屏），PNG/JPEG 且无透明通道。
- [ ] 建议内容 1：双卡主页与“记录”。
- [ ] 建议内容 2：P1–P8 分析条。
- [ ] 建议内容 3：精确帧 P 点人工修正。
- [ ] 建议内容 4：画线与选择/移动。
- [ ] 建议内容 5：本地“记录”与标注导出。
- [ ] 截图必须显示真实 App 画面，不展示测试数据、个人通知或调试 UI。

## 发布资料 URL

- 隐私政策：`https://lb791203.github.io/SwingArc/app-store/privacy/`
- 支持：`https://lb791203.github.io/SwingArc/app-store/support/`

上述 URL 需在发布分支合并到 `main` 并启用 GitHub Pages（`main` / `/docs`）后再次打开验证。
