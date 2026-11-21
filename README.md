# BeautyShelf · 妆台

一个用 SwiftUI 打造的美妆 / 护肤品收纳 App：收纳你拥有的每一件，记录使用次数、剩余量和保质期。

## 功能
- 梳妆台式收纳：瓶子按层摆在架子上，可按分类筛选、搜索
- 每件产品一个玻璃瓶，液面高度 = 剩余量
- "用了一次"：累加次数、扣减用量，滴落 + 晃动 + 触感反馈
- 保质期：快到期和已过期的自动放到最上层"该先用掉"

## 设计
见 [DESIGN.md](DESIGN.md)。

## 运行
需要 Xcode 15+ / iOS 17+（SwiftData）。

```bash
brew install xcodegen
xcodegen generate
open BeautyShelf.xcodeproj
```
