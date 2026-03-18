# Claude Code Skills Manager

## 项目概述

一个开源的 Claude Code Skills 管理工具。核心是一个 ~300 行的 Bash 脚本 `sync.sh`，从多个 Git 仓库或本地目录同步 Skills 到 `~/.claude/skills/`。

## 架构设计

### 核心思想

**单文件架构** — 所有逻辑在 `sync.sh` 一个文件中，不做模块拆分。Shell 脚本的可维护性来自清晰的注释分段，不来自文件拆分。

**文件即配置** — 源管理通过 `sources.d/` 目录实现，每个 `.conf` 文件就是一个源。添加源 = 创建文件，删除源 = 删除文件，无需维护集中配置。

**标记即状态** — 每个已安装 Skill 目录下的 `.source` 文件（一行文本 `source_name|timestamp`）是唯一的状态存储，不使用 JSON/YAML 等结构化元数据。

### 数据流

```
sources.d/*.conf → git clone (sparse) → 发现 SKILL.md → 哈希比对 → 安装/更新 → .source 标记 → setup.conf 检查 → post-install.sh
```

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| 脚本语言 | Bash | 零依赖，Claude Code 用户一定有 Bash |
| 状态存储 | `.source` 文本文件 | 比 JSON 简单，shell 可直接 `cut` 解析 |
| 多源配置 | `sources.d/` 目录 | 比单文件多行更直观，天然支持增删 |
| 变更检测 | MD5 哈希比对 | 准确、跨平台（macOS `md5` / Linux `md5sum`） |
| Git 拉取 | sparse checkout + shallow clone | 只拉需要的子目录，省带宽 |
| Token 存储 | 引用环境变量名 | conf 文件不含敏感信息，可安全提交 |
| 路径展开 | `${1/#\~/$HOME}` | 避免 `eval` 注入风险 |
| post-install | 默认执行 | 信任边界在源级别，添加源即表达信任 |

### sync.sh 代码结构

```
第 1-13 行    文件头注释和 Usage
第 14-83 行   配置变量 + 参数解析（--dry-run/--only/--source/--list/--remove/--no-hooks）
第 85-115 行  工具函数（info/warn/error/cleanup/expand_tilde/file_hash/now_iso/get_skill_source）
第 117-147 行 --list 模式：遍历 skills 目录，读 .source 标记，格式化输出
第 149-170 行 --remove 模式：校验 .source 归属后删除
第 172-201 行 同步模式入口：校验 sources.d 目录和 .conf 文件
第 207-411 行 主循环：遍历每个源 → fetch → discover → compare → install/update
第 413-421 行 汇总统计
第 423-472 行 setup.conf 配置检查（仅对本次变更的 skill）
第 474-491 行 post-install.sh 钩子执行
第 493-500 行 完成提示
```

### 安全模型

- **信任边界在源级别**：用户添加源 = 信任该源全部内容
- **Token 不入库**：conf 文件存环境变量名（`GIT_TOKEN_ENV=VAR_NAME`），不存值
- **无 eval**：`~` 展开用纯字符串替换
- **不碰手动 Skill**：无 `.source` 标记的 Skill 跳过

### 冲突处理

多源同名 Skill：按 `sources.d/` 文件名字母序先到先得。已安装的 Skill 保留原始来源，其他源同名 Skill 跳过并告警。手动切换需先 `--remove` 再重新指定 `--source` 安装。

### 跨平台兼容

- macOS 用 `md5 -q`，Linux 用 `md5sum`，通过 `command -v` 自动选择
- `date -u` 生成 ISO 时间戳
- `find -print0` + `read -d ''` 处理含空格文件名

## Skill 规范

### 必须文件

- `SKILL.md` — YAML frontmatter（name、description）+ Markdown 正文

### 可选文件

- `setup.conf` — 前置依赖声明，格式 `type|name|help`（type: env/file/note）
- `post-install.sh` — 安装后初始化脚本
