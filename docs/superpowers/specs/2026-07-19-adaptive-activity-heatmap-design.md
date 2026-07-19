# 自适应活跃热力图设计

## 背景

`GET /api/desktop/usage` 会根据时间范围返回不同粒度的 bucket：短周期使用小时级数据，30D/90D 使用日级数据，全部范围未来可能使用月级数据。当前客户端忽略 `coverage.granularity`，始终把 `bucketStart` 解析成“星期 × 小时”。日级 bucket 的时间统一为 `00:00:00Z`，转换到北京时间后全部落在 08:00，导致 30D/90D 热力图错误地显示为一条竖线。

## 目标

- 小时级数据继续使用现有的 7 × 24 分时热力图。
- 日级数据使用日期日历热力图，不从日级 bucket 伪造小时分布。
- 月级数据使用按月活跃图，不从月级 bucket 伪造日期或小时分布。
- 保留 Token/费用切换、强度图例和悬停详情。
- 不增加网络请求，不增加服务器或数据库负载。
- 旧后端未返回 `coverage` 时保持小时热力图兼容行为。

## 数据契约

客户端为 `UsageResponse` 增加可选字段：

```swift
let coverage: UsageCoverage?
```

`UsageCoverage` 解码：

- `requestedStart: String?`
- `requestedEnd: String?`
- `dataStart: String?`
- `dataEnd: String?`
- `complete: Bool`
- `granularity: UsageGranularity`

`UsageGranularity` 支持 `hour`、`day`、`month`、`mixed` 和未知值。未知或缺失值回退到现有小时视图，避免旧接口导致空白页面。

## 展示规则

### 小时级

- 适用：`granularity == hour`，以及旧后端未返回粒度。
- 标题：`分时活跃`。
- 结构：纵向周一至周日，横向 00–23 点。
- 聚合：按本地时区的 weekday/hour 聚合 Token 或费用。

### 日级

- 适用：`granularity == day`。
- 标题：`每日活跃`。
- 结构：纵向周一至周日，横向按自然周排列。
- 30D 通常约 5–6 列，90D 通常约 13–14 列；列宽根据容器宽度自适应。
- 同一日期下不同 source/model/project bucket 先汇总，再映射到该日期单元格。
- 日期必须从 `bucketStart` 的 UTC 日期部分读取，不能先转本地时间，否则 `00:00Z` 会跨时区偏移日期。
- 悬停显示完整日期、Token 或费用。

### 月级

- 适用：`granularity == month`。
- 标题：`每月活跃`。
- 结构：按月份顺序显示紧凑强度单元格；月份过多时横向压缩或滚动，但不显示虚假的星期/小时坐标。
- 同一个月不同维度 bucket 先汇总。
- 悬停显示年月、Token 或费用。

### 混合粒度

- `granularity == mixed` 时不把不同粒度直接混入同一热力图。
- 优先按 bucket 时间跨度判断可安全展示的最低公共粒度；无法确定时显示清晰的“当前范围包含混合粒度，暂不提供活跃分布”，不生成误导图形。

## 组件边界

- `UsageBucket.swift`：只负责解码覆盖范围和粒度。
- `AppState.swift`：保存当前响应的 coverage，并把粒度纳入热力图缓存键，切换范围后必须重算。
- `DashboardData.swift`：保留小时聚合，并新增独立的日级/月级聚合模型。每个模型只处理一种粒度。
- `ActivityHeatmapView.swift`：根据粒度选择小时、日历或月级视图；Token/费用状态跨视图保留。

## 空数据与兼容

- 当前粒度没有可解析 bucket 时，在卡片内显示“暂无活跃数据”。
- `coverage` 缺失时使用小时视图，兼容旧后端和现有测试桩。
- 不使用 bucket 数量或时间是否为整点猜测接口粒度；后端已提供明确的 `coverage.granularity`。
- `coverage.complete == false` 不影响图形结构，但界面只展示实际返回数据，完整性提示由范围状态区域另行处理，不在本次改动中扩展。

## 性能

- 聚合只在响应、范围、筛选或 Token/费用模式变化时计算。
- 日级聚合最多约 90 天；月级聚合远小于日级，均可在本地同步完成。
- 继续复用现有 memoizer，不在 SwiftUI `body` 内重复扫描 bucket。
- 不新增动画层、网络请求或后台轮询。

## 测试

1. 解码带 `coverage.granularity = day` 的接口响应。
2. 旧响应缺少 coverage 时正常解码并回退小时视图。
3. 日级 bucket `2026-07-01T00:00:00Z` 在 Asia/Shanghai 下仍归入 7 月 1 日，而不是 7 月 1 日 08:00 的小时格。
4. 同一日期的多个 bucket 正确汇总 Token 和费用。
5. 30D/90D 日历布局覆盖正确的周数和星期位置。
6. 小时级现有 weekday/hour 聚合测试保持通过。
7. 切换响应粒度会使热力图缓存失效。
8. 月级 bucket 按年月汇总，不进入小时或日级坐标。
9. 全量测试、Release 构建和安装包签名验证通过。

## 验收标准

- 30D/90D 不再出现所有数据集中在 08 点的一条竖线。
- 短周期分时热力图外观和行为不退化。
- 日级和月级图表的标题、坐标和悬停内容与数据粒度一致。
- Token/费用切换结果与 bucket 汇总值一致。
- 不增加后端调用和数据库负载。
