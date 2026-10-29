# 铃渡（Knockwater）

竖屏单指物理解谜：水铃每走一步荡开一圈波，用波前把花瓣推回湾心。

## 当前状态

- Flutter 3.47 / Dart 3.13，7 章 78 关（8 / 12 / 12 / 12 / 12 / 16 / 6）。
- 普通关每关 3 条、第七章每关唯一解，均经 0.62s / 0.9s 双节奏复验，共 222 条；见 `SOLUTIONS.md` / `BEST_SOLUTIONS.md`。
- 6 种池塘轮廓按关轮换并配套水色；第七章为重叩失效的芦苇迷径长道（10–12 步唯一解），配涡流、回音石与暗流。
- 第 1 关为“教学 · 三步”关卡：走一步、重叩、送花瓣入湾。
- 支持八方向拖动（键盘 W+A / W+D / S+A / S+D 或 Q/E/C/V 斜向）、重叩蓄力（0.8s 满蓄）、撤销、重开、落定、搁浅、暗流、墨石、回音石、芦苇与终章结算。
- 存档与选关：`shared_preferences` 保存通关/星级/继续位置；另存最近一次“安静水面”局内检查点（不保存飞行中的波前）；关卡顺序解锁，未解锁关不可选。
- 难度：普通关铃息按 3 条 canonical 的最大成本 + 1 预算；第七章铃息恰好等于唯一长道步数。
- 111 项自动化测试；`flutter analyze` 无问题。

## 运行

```bash
C:\Android\flutter\bin\flutter.bat pub get
C:\Android\flutter\bin\flutter.bat run
C:\Android\flutter\bin\flutter.bat test
# 跑测试前关闭 Web 预览/Chrome；若 Windows 上全套 runner 偶发 did not complete，
# 可按 test/*_test.dart 逐文件运行（本机逐文件 111/111 通过）。
C:\Android\flutter\bin\flutter.bat analyze
```

Web 预览（可选）：

```bash
C:\Android\flutter\bin\flutter.bat build web --release
python -m http.server 5180 --directory build/web
# 开发调试可用 ?level=N；发布版只能进入已解锁关
```

## 代码结构

- `lib/main.dart`：页面、八向拖动/键盘输入、HUD、选关、弹层与终章结算。
- `lib/game/progress.dart`：存档、顺序解锁、星级与继续位置。
- `lib/game/engine.dart`：固定 1/60 步长、波前、花瓣、机关、胜负与撤销。
- `lib/game/levels.dart`：78 关数据（7 章）。
- `lib/game/painter.dart`：水墨水面与动效。
- `lib/game/sfx.dart`：音频加载、播放与静音。
- `tool/solver.dart` / `verify_solutions.dart` / `collect_solutions.dart`：求解、双节奏复验与解法语料生成。
- `test/`：引擎、输入方向、关卡可解性、初始状态、存档解锁、选关流程、渲染重建、完整流程测试。

## 文档

- `SPEC.md`：工程与规则规范。
- `DESIGN.md`：游戏设计案。
- `DEVELOPMENT_PLAN.md`：后续方案与里程碑。
- `SOLUTIONS.md`：78 关推荐解（222 条）。
- `BEST_SOLUTIONS.md`：每关最佳解（78 条）。
- `OPTIMIZATION.md`：优化方向。
