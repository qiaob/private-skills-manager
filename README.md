# Private Marketplace for Claude Code

搭建团队私有的 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) Plugin Marketplace。Fork 本仓库，添加你的 Plugin，团队成员通过 `/plugin` → `Marketplaces` → `+ Add Marketplace` 即可使用。

## 快速开始

### 1. Fork 本仓库

在 GitHub 上 fork 到你的组织（可设为 private repo）。

### 2. 初始化

```bash
git clone git@github.com:your-org/your-marketplace.git
cd your-marketplace
bash manage.sh init my-marketplace --owner "Your Team" --email "team@example.com"
```

### 3. 添加 Plugin

**新建 Plugin：**

```bash
bash manage.sh add db-query -d "Query production database" -c database -a "Backend Team"
# 编辑生成的 SKILL.md
vim plugins/db-query/skills/db-query/SKILL.md
```

**导入已有 Skill：**

```bash
bash manage.sh import ~/.claude/skills/my-existing-skill
```

### 4. 提交并推送

```bash
git add -A && git commit -m "add db-query plugin" && git push
```

### 5. 团队成员使用

在 Claude Code 中：

```
/plugin → Marketplaces → + Add Marketplace → your-org/your-marketplace
```

之后在 `Discover` 标签下即可安装。

## 管理命令

```bash
manage.sh init <name> --owner "x" [--email "x"] [--description "x"]
manage.sh add <name> -d "description" [-c category] [-a author]
manage.sh import <skill-dir> [--as <plugin-name>]
manage.sh remove <name>
manage.sh list
manage.sh build                        # 从 plugins/ 重建 marketplace.json
manage.sh help
```

**Categories:** development, productivity, deployment, database, testing, security, monitoring, design, learning

## Plugin 结构

每个 Plugin 是 `plugins/` 下的一个目录：

```
plugins/my-plugin/
├── .claude-plugin/
│   └── plugin.json            # 插件元数据（manage.sh 自动生成）
└── skills/
    └── my-plugin/
        ├── SKILL.md           # Skill 描述和指令
        └── ...                # 其他支持文件
```

### SKILL.md

```markdown
---
name: my-plugin
description: |
  描述这个 Skill 做什么。
  Trigger when: 触发条件。
---

给 Claude 的具体指令...
```

### plugin.json

由 `manage.sh` 自动生成和维护，格式为：

```json
{
  "name": "my-plugin",
  "description": "Plugin description",
  "author": { "name": "Author" }
}
```

## 批量导入已有 Skills

```bash
for d in ~/.claude/skills/*/; do
  [ -f "$d/SKILL.md" ] && bash manage.sh import "$d"
done
```

## 私有仓库访问

团队成员需要对 GitHub 仓库有读取权限。确保：
- 成员已加入 GitHub Organization
- 仓库设为 Organization 可见（Internal）或明确授权

Claude Code 使用本机的 Git 凭证（SSH key 或 `gh auth`）拉取 Marketplace。

## 许可证

MIT
