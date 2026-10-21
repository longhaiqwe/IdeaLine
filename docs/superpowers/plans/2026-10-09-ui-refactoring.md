# UI 重构与设计系统优化实现方案 (UI Refactoring Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根据《Refactoring UI》设计规范与系统审查结果，重构“灵感晾台”的 UI 层，建立统一设计 Token（字阶、墨阶、圆角、光源深度），修复 P0/P1 可用性与层级缺陷，提升原生 macOS 桌面质感。

**Architecture:**
1. 在 `Views.swift` 顶部建立轻量级 Design Tokens（墨阶灰度、阶梯字号、圆角规范、两层光影规范）。
2. 按组件依次重构：`HangingNote`（卡片热区/字号/阴影）→ `ClotheslineView`（主次操作与空状态）→ `ComposerView`（基线对齐/颜色选择器指示器/窗口圆角）→ `LibraryView`（搜索栏胶囊/悬浮反馈/主次操作）。
3. 调整 `AppDelegate.swift` 中浮动面板的透明度支持，使窗口圆角自然呈现。

**Tech Stack:** macOS 14+, Swift 5.9+, SwiftUI, AppKit (无外部第三方依赖).

## Global Constraints
- 必须保证 `swift test` 持续 100% 通过。
- 每次修改前必须中文阐明设计原理，修改后解释具体改动。
- 保持原项目的纯本地、无依赖轻量级设计，不引入额外三方库。
- 遵循 Refactoring UI 规则编号（如 `§2.1`, `§3.6`, `§4.3`, `§5.6`, `§6.1.1` 等）。

---

### Task 1: 建立轻量级 Design Tokens 体系

**Files:**
- Modify: `Sources/IdeaLine/Views.swift:4-15`

**Interfaces:**
- Produces:
  - `Ink`: 统一的墨阶常数（`ink`, `inkSecondary`, `inkMuted`, `inkBorder`）。
  - `Typography`: 统一字阶标度（`fontSizeCaption: 11`, `fontSizeBody: 15`, `fontSizeSubhead: 18`, `fontSizeTitle: 26`, `fontSizeDisplay: 34`）。
  - `Radii`: 统一圆角（`radiusCard: 4`, `radiusWindow: 14`, `radiusPill: Capsule`）。
  - `Shadows`: 统一光源向下的正投影（`y>0, x=0`，两层深度规范）。

- [ ] **Step 1: 编写 Tokens 定义代码并在 Views.swift 中声明**

```swift
// MARK: - Design Tokens (Refactoring UI §1.5, §4.1, §5.2.1, §6.2.1)
let ink = Color(red: 0.20, green: 0.23, blue: 0.20) // 主墨色 #333B33
let inkSecondary = Color(red: 0.38, green: 0.42, blue: 0.38) // 次级墨色，满足 WCAG 4.5:1
let inkMuted = Color(red: 0.55, green: 0.58, blue: 0.55) // 弱化修饰墨色
let inkBorder = Color(red: 0.20, green: 0.23, blue: 0.20).opacity(0.10) // 边框墨色

let paper = Color(red: 0.97, green: 0.96, blue: 0.92)
let accent = Color(red: 0.69, green: 0.29, blue: 0.17)
let papers: [Color] = [
    Color(red: 1, green: 0.95, blue: 0.77),   // 0: 黄色
    Color(red: 0.88, green: 0.94, blue: 0.86), // 1: 绿色
    Color(red: 0.87, green: 0.93, blue: 0.97), // 2: 蓝色
    Color(red: 0.98, green: 0.87, blue: 0.83)  // 3: 粉色
]
func noteColor(_ i: Int) -> Color { papers[max(0, min(i, papers.count - 1))] }

enum AppTypeScale {
    static let caption: CGFloat = 11
    static let small: CGFloat = 12
    static let lead: CGFloat = 13
    static let body: CGFloat = 15
    static let subhead: CGFloat = 18
    static let title: CGFloat = 26
    static let display: CGFloat = 34
}
```

- [ ] **Step 2: 验证编译通过**

运行 `swift test` 确保无编译错误。

---

### Task 2: 重构便签卡片 (`HangingNote`)

**Files:**
- Modify: `Sources/IdeaLine/Views.swift:174-206`

**设计原理与变更目标:**
1. **可用性与无障碍 (`§4.3, §5.6`)**：将 9pt 文字升至 11pt，用 `inkSecondary` 替代容易失真的 `ink.opacity(0.45)`，确保粉色卡片上对比度 ≥ 4.5:1。
2. **热区防误触 (`§15.3`)**：为复制和收纳按钮增加 26×26pt 点击热区及按压/悬浮反馈，避免误触卡片进入编辑。
3. **视觉减负 (`§2.5.1`)**：去除每张便签左上角千篇一律的 `X 选题` 标签，仅保留日期；或调整为精致的编号/时间。
4. **统一正上方光源 (`§6.1.1, §6.3.a`)**：消除 `x: 1` 侧向偏光，改为 `x: 0` 的双层拟物投影（紧凑接触阴影 + 柔和环境光）。

- [ ] **Step 1: 在 `HangingNote` 中实现上述优化**
- [ ] **Step 2: 验证编译与测试**

---

### Task 3: 重构衣杆容器与空状态 (`ClotheslineView`)

**Files:**
- Modify: `Sources/IdeaLine/Views.swift:119-173`

**设计原理与变更目标:**
1. **明确首要操作 (`§2.8`)**：在悬浮控制胶囊中，将“新建选题”强化为主按钮（带深色微底色），翻页与总数作为次要操作。
2. **解决空状态重复入口 (`§8.4`)**：衣杆暂无选题时，屏幕中间已有大号引导卡片，此时底部胶囊隐藏多余的“新建选题”按钮，仅保留“全部选题”入口。
3. **按钮交互反馈 (`§6.2.2`)**：为翻页按钮增加悬浮底色高亮。

- [ ] **Step 1: 更新 `ClotheslineView` 交互布局**
- [ ] **Step 2: 验证编译与测试**

---

### Task 4: 重构书写弹窗与浮动窗口 (`ComposerView` & `AppDelegate`)

**Files:**
- Modify: `Sources/IdeaLine/Views.swift:60-101`
- Modify: `Sources/IdeaLine/AppDelegate.swift:124-132`

**设计原理与变更目标:**
1. **窗口圆角与质感 (`§1.4.3`)**：设置 `panel.isOpaque = false; panel.backgroundColor = .clear`，在 `ComposerView` 外层增加 `RoundedRectangle(cornerRadius: 14)` 和极细纸张边框，消除直角生硬感。
2. **基线对齐 (`§4.4`)**：顶部导航栏与底部保存按钮使用 `.firstTextBaseline` 对齐，解决 13pt 与 12pt 文字跳动。
3. **消除文案冗余 (`§2.1`)**：移除顶部标题下反复出现的“灵感晾台 / 记录选题”，使视觉焦点直达书写内容。
4. **颜色选择器无障碍指示器 (`§5.7`)**：选中的纸张色块增加内嵌中心点或内环，不再仅凭 1px 细线描边差异。
5. **外留白 > 内留白 (`§3.6`)**：规范分割线与底部辅助说明文字的间距。

- [ ] **Step 1: 调整 `AppDelegate.swift` 中 `FloatingPanel` 的背景属性**
- [ ] **Step 2: 重构 `ComposerView` 结构与排版**
- [ ] **Step 3: 验证编译与测试**

---

### Task 5: 重构全部选题管理页 (`LibraryView`)

**Files:**
- Modify: `Sources/IdeaLine/Views.swift:208-260`

**设计原理与变更目标:**
1. **表单控件品质 (`§8.1`)**：为搜索输入框构建原生质感的搜索胶囊容器（带图标、浅色背景与圆角），提升输入交互区域。
2. **卡片悬浮反馈 (`§6.2.2`)**：网格中的卡片在 Hover 时增加轻微阴影浮起与边框反馈，传达可点击属性。
3. **动作语义与层级区分 (`§2.8.1`)**：卡片本身的点击即代表“编辑”，下方文字按钮应将“收纳/重新挂起”作为主要辅助动作，“编辑”退居为次要提示，避免整行全红。
4. **文字阶梯归一化 (`§4.1`)**：使用统一字阶常量替换硬编码的 `35`, `19`, `10`。

- [ ] **Step 1: 实现 `LibraryView` 优化**
- [ ] **Step 2: 验证编译与测试**

---

### Task 6: 整体联调与构建验证

- [ ] **Step 1: 运行 `swift test` 验证数据逻辑与全部单元测试**
- [ ] **Step 2: 运行 `scripts/build-app.sh` 验证应用完整编译打包**
- [ ] **Step 3: 生成 Walkthrough 报告交付用户**
