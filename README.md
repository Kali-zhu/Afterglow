# 余香 · Afterglow

一个用 SwiftUI + SwiftData 打造的美妆 / 护肤品收纳 App：收纳你拥有的每一件，记录使用次数、剩余量和保质期。

## 功能
- **首次打开**：瓶子缓缓注满，"把梳妆台搬进手机"；「添加第一件」或「先看看示例」（示例可在设置里一键清除）
- **藏品**：顶部一张玻璃总览（藏品总值 / 件数 / 品牌 / 该先处理 / 备用）；按品类分层，每层横向滑动、放不下才滚，"该先用掉"（快到期 / 已过期 / 快用完）永远在最上层；分类胶囊带件数，备用库存显示 ×2；搜索名称或品牌
- **容器家族**：瓶 / 罐 / 管 / 面膜袋（显示剩余片数）/ 口红 / 粉盒，液面高度 = 剩余量，液面轻轻晃动（减弱动态效果时静止）；有照片时作为圆形标签贴在容器上
- **三种计量**：容量（ml / g，每次扣减用量）、按片计数（剩 7 / 共 10 片）、估算剩余 %（口红、眼影盘，在详情里直接拖动液面）
- **长按快捷菜单**：用了一次 / 编辑 / 用完了 / 删除
- **详情（唯一的「使用页」）**：首页、藏品、空瓶、近期记录点任何一件产品都打开它，产品图带着放大转场飞进来；大按钮「用了一次」（数字滚动 +1、剩余量和 14 天圆点即时更新、触感、短暂变成「已记下」并可撤销，不自动关闭）、开封 / PAO / EXP / 实际过期日、价格与每次成本；早间 / 晚间 / 化妆胶囊默认选中当前时段，记一次就带上这个时段
- **保质期**：包装到期日（EXP）与 开封日 + 开封后保质期（PAO）取更早的那个；没开封的第一次使用时自动记为今天开封
- **使用手记（首页）**：一张玻璃卡显示最近用过的那件，点卡片或「去记这一次」打开这件产品的详情（唯一的「使用页」），在详情里记一次；多件时「再记这 N 件」一键批量记。下面是「连续 N 天 + 最近七天点阵」，今天还没记不清零，只鼓励不惩罚
- **今日（小仪式）**：当前时段（15:00 前早间，之后晚间）的产品按顺序排成一排"托盘"大卡片（有抠图显示实物，否则显示容器）；点「拿起来用」或把卡片往上推 = 记一次使用，卡片滑进下方"已用"一摞（轻点可撤销），伴随触感；顶部进度环；全部用完时环合拢，出现"晚间护肤完成，晚安"。「调整」里挑选产品、拖动排序（顺序按产品 uid 存在 App Group，小组件同序）。右上角可切换紧凑清单（大字号时默认清单）
- **小组件**：「今晚该用」（小 / 中）显示当前流程和进度，直接在桌面勾选（AppIntent，已勾再点撤销）；「快过期」（小 / 中 + 锁屏长条 / 圆形）显示最快过期的几件和剩余天数，按状态着色。午夜、15:00 自动刷新，App 内任何修改保存后也会刷新
- **空瓶记分享图**：空瓶页「生成空瓶记」→ 选按月 / 按年 → 生成 1080×1440 竖图（空瓶摆在架子上、"11 月空瓶 · 4 件"、每件用了几次和 ¥/次、妆台字标）→ 分享或存相册，发小红书刚好
- **空瓶**：玻璃统计卡（今年用空 / 用完的价值 / 平均每次 / 平均用多久）+ 待补货 + 空瓶墙（空的磨砂瓶站在玻璃架板上，下面写用了几次、用了多久、每次多少钱；买到了 → 藏品多一件同款或备用库存 +1）
- **用完了**：容器倾斜倒空的动画 → 移入空瓶墙 → 询问是否加入补货清单（有备用库存时可直接开一瓶备用的）
- **15 秒添加**：拍照 / 相册（裁成方形）、名称、品牌、形状图块、容量快捷胶囊、每次用量 少量 / 适中 / 多、日期胶囊（开封、6M/12M/24M/36M、1/2/3 年后）+ 实时"会在 X 过期（按…算）"、折叠的「更多」（价格、备用库存、液体颜色、加入早间 / 晚间）
- **本地提醒**：到期前 30 天、7 天；剩余不到 15% 提醒补货；每晚 21:30 晚间流程提醒（可关）——在设置里开关
- **无障碍**：减弱动态效果（托盘不做位移动画、液面静止）、动态字体、VoiceOver 标签（"剩 31 ml"）、可调节的估算液面、≥ 44pt 触控目标、深色模式

## 代码结构
```
BeautyShelf/
  App/        入口、RootView（欢迎页 / 标签页）、MainTabView、AppCoordinator
  Models/     Product（SwiftData）、SampleData
  Design/     Theme、容器几何（ContainerShapes）、ContainerView（晃动液面）
  Views/      Shelf（妆台、卡片、详情）、Today、Finished、Editor（表单、相机）、Welcome、Settings、Components
  Services/   NotificationService（本地通知）、ImageTools（方形裁切）、
              SharedStore（App Group 共享数据库 / 流程顺序 / 抠图缩略图）、ShareCard（空瓶记分享图）
Widgets/      小组件扩展 BeautyShelfWidgets：今晚该用（LogRoutineIntent）、快过期
Entitlements/ App 与小组件的 App Group 权限
```

数据：SwiftData 数据库放在 App Group `group.com.llmzhu.BeautyShelf` 里（`ModelConfiguration(groupContainer:)`），App 和小组件读写同一份。旧版本放在 App 沙盒里的数据库会在第一次启动时自动搬过去。App 里的修改经 `AppCoordinator.dataChanged()` 防抖保存并 `WidgetCenter.shared.reloadAllTimelines()`；小组件里勾选后，App 回到前台时会换一个新的 ModelContext 重新读取。

## 设计
见 [DESIGN.md](DESIGN.md)；产品方案见 [PRODUCT.md](PRODUCT.md)。

## 运行
需要 Xcode 15+ / iOS 17+（SwiftData）。

```bash
brew install xcodegen
xcodegen generate
open BeautyShelf.xcodeproj
```

**签名（小组件必需）**：在 Xcode 里给 `BeautyShelf` 和 `BeautyShelfWidgets` 两个 target 选同一个 Team，并在 Signing & Capabilities 里确认 **App Groups** 已勾选 `group.com.llmzhu.BeautyShelf`（权限文件已在 `Entitlements/`，个人账号需要在开发者后台或让 Xcode 自动注册这个 App Group；如果换了 bundle 前缀，同时改 `SharedStore.appGroup` 和两个 entitlements）。没开 App Group 时 App 仍能运行，但数据存在 App 自己的沙盒里，小组件读不到。
