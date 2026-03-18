# Private Marketplace for Claude Code

## 项目概述

一个可直接 fork 的私有 Claude Code Plugin Marketplace 模板。兼容 Claude Code 内置的 `/plugin` → `Marketplaces` 机制。

## 架构设计

### 核心思想

**兼容官方格式** — 完全遵循 `anthropics/claude-plugins-official` 的仓库结构和 JSON Schema，Claude Code 原生支持安装/更新/发现。

**模板仓库** — fork 即用。`manage.sh` 负责自动化 plugin 的创建、导入和 `marketplace.json` 的维护，降低手工编辑 JSON 的出错率。

**零运行时依赖** — 管理脚本只需 bash + python3（JSON 操作），不引入 jq、yq 等额外工具。

### 仓库结构

```
.claude-plugin/
└── marketplace.json          # Marketplace 注册表（manage.sh 维护）
plugins/
└── <plugin-name>/
    ├── .claude-plugin/
    │   └── plugin.json       # Plugin 元数据
    └── skills/
        └── <skill-name>/
            └── SKILL.md      # Skill 定义
manage.sh                     # 管理脚本
```

### marketplace.json 格式

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "marketplace-name",
  "description": "...",
  "owner": { "name": "...", "email": "..." },
  "plugins": [
    {
      "name": "plugin-name",
      "description": "...",
      "source": "./plugins/plugin-name",
      "category": "development"
    }
  ]
}
```

### manage.sh 命令

| 命令 | 作用 |
|------|------|
| `init` | 初始化 marketplace.json（设置名称、owner） |
| `add` | 创建新 plugin 骨架 + 更新 marketplace.json |
| `import` | 导入已有 SKILL.md 目录为 plugin |
| `remove` | 删除 plugin + 更新 marketplace.json |
| `list` | 列出所有 plugin |
| `build` | 从 plugins/ 目录重建 marketplace.json |

### 关键设计决策

| 决策 | 选择 | 原因 |
|------|------|------|
| JSON 操作 | python3 + 环境变量传参 | 避免 heredoc 引号地狱，python3 几乎所有系统自带 |
| YAML 解析 | python3 正则提取 frontmatter | 只需 name/description，不值得引入 PyYAML |
| marketplace.json | 由脚本自动维护 | 避免手工编辑 JSON 出错 |
| build 命令 | 从 plugin.json 重建 | 保留手动编辑 plugin.json 的灵活性 |

### Plugin 发现机制

Claude Code 通过以下路径使用 Marketplace：
1. 用户通过 `/plugin` → `+ Add Marketplace` 添加 GitHub 仓库
2. Claude Code clone 仓库到 `~/.claude/plugins/marketplaces/<name>/`
3. 读取 `.claude-plugin/marketplace.json` 获取 plugin 列表
4. 用户在 `Discover` 标签选择安装
5. Plugin 安装到 `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`
6. 安装记录写入 `~/.claude/plugins/installed_plugins.json`
