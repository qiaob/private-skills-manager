# Claude Code Skills Manager

从多个 Git 仓库或本地目录同步 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) Skills。

## 安装

```bash
git clone https://github.com/user/skills-manager.git ~/.claude/skills/skills-manager
```

## 使用

### 1. 添加源

在 `sources.d/` 下创建 `.conf` 文件，文件名即源名：

```bash
cat > ~/.claude/skills/skills-manager/sources.d/my-source.conf << 'EOF'
REPO=https://github.com/org/skills-repo.git
BRANCH=main
SKILLS_SUBDIR=skills
EOF
```

### 2. 同步

```bash
# 安装/更新所有 Skills
bash ~/.claude/skills/skills-manager/sync.sh

# 或在 Claude Code 中直接说："install skills" / "update skills"
```

### 3. 其他操作

```bash
sync.sh --dry-run             # 仅检查，不修改
sync.sh --list                # 列出已安装 Skills
sync.sh --only <skill-name>   # 只同步指定 Skill
sync.sh --source <source>     # 只同步指定源
sync.sh --remove <skill-name> # 移除 Skill
sync.sh --no-hooks            # 跳过 post-install.sh
```

可组合：`sync.sh --source work --only my-skill`

## 源配置

### 公开仓库（HTTPS）

```conf
REPO=https://github.com/org/repo.git
BRANCH=main
SKILLS_SUBDIR=skills
```

### 私有仓库（SSH + 指定私钥）

适用于多 GitHub 账号场景：

```conf
REPO=git@github.com:org/repo.git
BRANCH=main
SKILLS_SUBDIR=skills
SSH_KEY=~/.ssh/id_ed25519_work
```

### 私有仓库（HTTPS + Token）

Token 不写入配置文件，只引用环境变量名：

```conf
REPO=https://github.com/org/repo.git
BRANCH=main
SKILLS_SUBDIR=skills
GIT_TOKEN_ENV=GITHUB_TOKEN
```

```bash
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx  # 在 shell 配置中设置
```

### 本地目录

开发调试自己的 Skill 时使用：

```conf
REPO=~/projects/my-skills
TYPE=local
SKILLS_SUBDIR=skills
```

### 字段参考

| 字段 | 必填 | 默认 | 说明 |
|------|------|------|------|
| `REPO` | 是 | - | Git 仓库地址或本地路径 |
| `BRANCH` | git 源必填 | - | 分支名 |
| `SKILLS_SUBDIR` | 是 | - | Skills 所在子目录 |
| `TYPE` | 否 | `git` | `git` 或 `local` |
| `SSH_KEY` | 否 | 系统默认 | SSH 私钥路径 |
| `GIT_TOKEN_ENV` | 否 | - | Token 环境变量名 |

## 编写 Skill

仓库中每个包含 `SKILL.md` 的子目录会被自动识别为一个 Skill：

```
your-repo/skills/
├── my-skill/
│   ├── SKILL.md           # 必须 — Skill 描述和触发规则
│   ├── setup.conf         # 可选 — 声明前置依赖
│   ├── post-install.sh    # 可选 — 安装后自动执行
│   └── helper.sh          # 其他文件
└── another-skill/
    └── SKILL.md
```

### SKILL.md

```markdown
---
name: my-skill
description: |
  描述这个 Skill 做什么。
  Trigger when: 用户说了什么关键词时触发。
---

给 Claude 的具体指令...
```

### setup.conf（可选）

声明 Skill 运行需要的环境变量、文件或前置条件：

```conf
env|API_TOKEN|从 https://example.com 获取 Token
file|~/.config/tool/config.json|运行 tool init 生成
note||需要先安装 tool: brew install tool
```

### post-install.sh（可选）

安装或更新后自动执行。适合生成索引、构建 Schema 等初始化操作。

## 多源与冲突

- 多个源可以同时使用，按文件名字母序处理
- 同名 Skill 先到先得，后到的跳过并告警
- 手动放在 `~/.claude/skills/` 的 Skill 不会被修改或删除
- 切换来源：`sync.sh --remove X && sync.sh --only X --source other`

## 许可证

MIT
