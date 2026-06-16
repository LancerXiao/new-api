# API.ENLYAI.COM — New API 网关部署与使用文档

> 版本：v2.0 | 更新日期：2026-06-09 | New API 版本：calciumion/new-api:latest

---

## 一、系统概览

| 项目 | 详情 |
|------|------|
| 服务地址 | https://api.enlyai.com |
| 管理后台 | https://api.enlyai.com |
| API Base URL | `https://api.enlyai.com/v1` |
| New API 版本 | calciumion/new-api:latest |
| 部署方式 | Docker 独立容器 (PostgreSQL + Redis + New API) |
| SSL 证书 | Let's Encrypt，有效期至 2026-09-06，自动续期 |
| 服务器 | 阿里云 ECS (114.215.183.45) |
| 自用模式 | 已关闭 |
| 用户注册 | 已开启 |

---

## 二、API Key 池配置

### 2.1 渠道（Channel）总览

| 状态 | 数量 | 说明 |
|------|------|------|
| 启用（status=1） | 82 | 全部渠道启用 |
| 禁用 | 0 | 无禁用渠道 |

### 2.2 渠道来源

| 来源 | 数量 | Base URL | 说明 |
|------|------|----------|------|
| free-llm-gateway | 2 | gateway-production-f831.up.railway.app | Railway 部署的免费网关 |
| free-key-sync-* | ~47 | aiapiv2.pekpik.com | 从 GitHub 自动同步的免费 Key |
| 其他渠道 | ~33 | aiapiv2.pekpik.com | 历史导入的 Key |

### 2.3 关键配置

- **auto_ban = 0**：所有渠道关闭自动封禁，避免因临时错误导致渠道被禁用
- **group = default**：所有渠道属于 default 分组
- **priority = 3, weight = 3**：统一优先级和权重

---

## 三、免费 Key 来源

### 3.1 当前唯一 Key 源

**当前 API Key 的唯一来源是 [alistaitsacle/free-llm-api-keys](https://github.com/alistaitsacle/free-llm-api-keys)**

| 仓库 | Stars | Key 格式 | Base URL | 采集方式 | 有效期 |
|------|-------|----------|----------|----------|--------|
| [alistaitsacle/free-llm-api-keys](https://github.com/alistaitsacle/free-llm-api-keys) | ~1,790 | `sk-` 前缀 | `https://aiapiv2.pekpik.com` | Python 脚本自动提取 Key-Model 对 | 24-48小时 |

**该仓库特点**：
- 提供 49 个 Key，覆盖 90+ 模型
- 每个 Key 只能访问特定模型（Key-Model 绑定）
- Key 每日更新，有效期 24-48 小时
- 上游端点 `aiapiv2.pekpik.com` 兼容 OpenAI SDK 格式
- 支持 `smart-chat` 模型自动路由到最健康模型

### 3.2 可集成的更多免费 Key 源仓库

#### 类型一：共享 API Key 仓库（直接提供密钥）

目前只有 `alistaitsacle/free-llm-api-keys` 是唯一直接共享 API Key 的仓库。

#### 类型二：免费 API 资源列表（需自行注册获取 Key）

| 仓库 | Stars | 说明 |
|------|-------|------|
| [cheahjs/free-llm-api-resources](https://github.com/cheahjs/free-llm-api-resources) | 22,900+ | 最全免费 LLM API 资源列表 |
| [mnfst/awesome-free-llm-apis](https://github.com/mnfst/awesome-free-llm-apis) | 4,900+ | 永久免费层级列表 |
| [tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi) | 6,200+ | 自托管 API 网关 |

#### 类型三：免费 API 提供商（需注册但免费）

| 提供商 | 免费额度 | 支持模型 | 注册地址 |
|--------|----------|----------|----------|
| Google AI Studio | 20次/天 | Gemini 2.5 Flash | [aistudio.google.com](https://aistudio.google.com/apikey) |
| Groq | 14,400次/天 | Llama 3.3 70B, Qwen3 | [console.groq.com](https://console.groq.com) |
| Cerebras | 免费推理 | Qwen3 235B | [cloud.cerebras.ai](https://cloud.cerebras.ai) |
| Cohere | 1,000次/月 | Command A | [dashboard.cohere.com](https://dashboard.cohere.com) |
| Mistral | 10亿 tokens/月 | Mistral Large 3 | [console.mistral.ai](https://console.mistral.ai) |
| OpenRouter | 20次/分钟 | 21个免费模型 | [openrouter.ai](https://openrouter.ai) |
| GitHub Models | 150次/天 | GPT-4o-mini | [github.com](https://github.com/marketplace/models) |
| SambaNova | 免费推理 | DeepSeek V3.x | [cloud.sambanova.ai](https://cloud.sambanova.ai) |

### 3.3 Key 搜集方式详解

#### 自动搜集（Python 脚本）

**脚本位置**：`/root/sync-free-keys.py`

**工作流程**：
1. 通过 GitHub API / Raw URL / git clone 三种方式获取 README.md（自动降级）
2. 使用 Python 正则提取 Key-Model 对（格式：`| sk-xxx | model-name |`）
3. 去重后清理旧的 sync 渠道
4. 通过 SQL 直接插入 channels 和 abilities 表
5. 更新非 sync 渠道的 abilities 记录

**关键代码逻辑**：
```python
# 从 README 提取 Key-Model 对
pairs = re.findall(
    r'\| `sk-([a-zA-Z0-9_-]+)` \| ([a-zA-Z0-9_/.:-]+) \|',
    content
)
```

**添加新的 Key 源仓库**：编辑 `/root/sync-free-keys.py`，在 `KEY_SOURCES` 列表中添加：
```python
KEY_SOURCES = [
    {
        "repo": "alistaitsacle/free-llm-api-keys",
        "file": "README.md",
        "branch": "main"
    },
    # 添加新源：
    # {
    #     "repo": "用户名/仓库名",
    #     "file": "README.md",
    #     "branch": "main"
    # },
]
```

#### 手动搜集（适用于免费 API 提供商）

1. 访问提供商官网注册账号
2. 在控制台获取 API Key
3. 在 New API 管理后台 → 渠道管理 → 添加渠道
4. 填写 Base URL（不要包含 /v1）和 Key

---

## 四、模型配置

### 4.1 /v1/models 返回的模型（22个）

以下模型通过 abilities 表配置，动态展示在模型列表中：

| 模型 | 类型 | 免费标识 |
|------|------|----------|
| baidu/cobuddy:free | 百度 Cobuddy | 免费 |
| claude-3-haiku | Anthropic Claude 3 Haiku | |
| deepseek-chat | DeepSeek Chat | |
| deepseek-coder | DeepSeek Coder | |
| deepseek/deepseek-v4-pro | DeepSeek V4 Pro | |
| gemini-2.5-flash | Google Gemini 2.5 Flash | |
| google/gemini-3.1-flash-lite | Google Gemini Lite | |
| gpt-3.5-turbo | OpenAI GPT-3.5 Turbo | |
| gpt-4o | OpenAI GPT-4o | |
| gpt-4o-mini | OpenAI GPT-4o Mini | |
| ibm-granite/granite-4.1-8b | IBM Granite | |
| inclusionai/ling-2.6-1t:free | InclusionAI Ling | 免费 |
| inclusionai/ring-2.6-1t | InclusionAI Ring | |
| mistralai/mistral-medium-3-5 | Mistral Medium | |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | NVIDIA Nemotron | 免费 |
| poolside/laguna-m.1:free | Poolside Laguna M | 免费 |
| poolside/laguna-xs.2:free | Poolside Laguna XS | 免费 |
| qwen/qwen3.6-27b | 通义千问 27B | |
| qwen/qwen3.6-35b-a3b | 通义千问 35B | |
| qwen/qwen3.6-flash | 通义千问 Flash | |
| qwen/qwen3.6-max-preview | 通义千问 Max | |
| text-embedding-3-small | 文本嵌入模型 | |

> 注意：abilities 表中共有 34 个模型，部分模型可能因渠道 Key 失效而未在 /v1/models 中显示。每次 Key 同步后会自动更新。

### 4.2 模型广场动态刷新

- **刷新频率**：每 30 分钟（与 Key 同步同步执行）
- **实现方式**：sync 脚本每次运行时清理旧的 sync 渠道和 abilities 记录，重新插入最新数据
- **Crontab**：`*/30 * * * * python3 /root/sync-free-keys.py >> /var/log/sync-free-keys.log 2>&1`

---

## 五、自动刷新与有效性检测

### 5.1 自动刷新频率

| 任务 | 频率 | 实现方式 |
|------|------|----------|
| GitHub 免费 Key 同步 | 每 30 分钟 | crontab: `*/30 * * * * python3 /root/sync-free-keys.py` |
| 渠道健康检测 | New API 内置 | ChannelUpdateFrequency 配置 |
| SSL 证书续期 | 每天 3:00 | crontab: `0 3 * * * certbot renew --quiet --post-hook 'nginx -s reload'` |

### 5.2 Key 有效性自动检测

**New API 内置机制**：
- 渠道请求失败时，New API 会记录失败次数
- `auto_ban = 0`：关闭了自动封禁，避免因临时错误导致渠道被禁用
- 失效的 Key 在下次 sync 时会被清理并替换为新 Key

**同步脚本机制**：
- 每次同步时清理所有旧的 `free-key-sync-*` 渠道
- 从 GitHub 重新获取最新 Key 并插入
- 同时更新 abilities 表，确保模型广场显示最新模型

### 5.3 同步日志

日志位置：`/var/log/sync-free-keys.log`

```bash
# 查看最近的同步记录
tail -20 /var/log/sync-free-keys.log

# 手动触发同步
python3 /root/sync-free-keys.py
```

---

## 六、管理员操作指南

### 6.1 登录管理后台

1. 访问 https://api.enlyai.com
2. 使用管理员账号登录：
   - 用户名：`root`，密码：`Enlyai2026!`
   - 用户名：`Lancer`，角色：管理员（role=100）

### 6.2 渠道管理

- 左侧菜单 → 渠道管理 → 查看所有渠道
- 添加渠道时 Base URL **不要包含 /v1**
- 由于 v1.0.0-rc.10 的渠道添加 API 存在 panic bug，批量操作建议通过数据库：
```bash
docker exec postgres psql -U newapi -d newapi -c "
INSERT INTO channels (name, type, key, base_url, models, \"group\", priority, weight, status, test_time, created_time, auto_ban)
VALUES ('渠道名', 1, 'sk-xxx', 'https://api.example.com', 'model1,model2', 'default', 3, 3, 1, 0, EXTRACT(EPOCH FROM NOW())::bigint, 0);
"
```

### 6.3 令牌管理

**当前主令牌**：

| 名称 | Key | 额度 | 有效期 |
|------|-----|------|--------|
| enlyai-master | `<YOUR_ADMIN_API_KEY>` | 无限 | 永久 |

**限制令牌只能使用某些模型**：
1. 编辑令牌 → 开启「模型限制」
2. 输入允许的模型名称（逗号分隔），如：`gemini-2.5-flash,qwen/qwen3.6-flash`

**设置令牌有效期**：
1. 编辑令牌 → 设置「过期时间」
2. 常用时间戳：1天后 `$(($(date +%s) + 86400))`，永不过期 `-1`

### 6.4 用户管理

**新用户注册**：
- 已开启注册（RegisterEnabled=true）
- 无需邮箱验证（EmailVerificationEnabled=false）
- 新用户默认分组：default
- 新用户默认额度：1,000,000

**限制用户只能使用某些模型**：
- 方法一（推荐）：为用户创建专用令牌，在令牌上设置模型限制
- 方法二：通过分组限制，创建不同分组并分配不同渠道访问权限

### 6.5 系统设置

| 设置项 | 当前值 | 说明 |
|--------|--------|------|
| SelfUseModeEnabled | **false** | 自用模式已关闭，首页不显示"自用模式" |
| RegisterEnabled | true | 允许用户注册 |
| EmailVerificationEnabled | false | 无需邮箱验证 |
| QuotaForNewUser | 1000000 | 新用户默认额度 |
| GroupForNewUser | default | 新用户默认分组 |

---

## 七、API 使用方法

### 7.1 快速开始

**注册账号**：
1. 访问 https://api.enlyai.com
2. 点击「注册」
3. 填写用户名和密码
4. 注册后在「令牌」页面创建自己的 API Key

**使用主 API Key**（管理员共享）：
```
<YOUR_ADMIN_API_KEY>
```

### 7.2 cURL 调用示例

**Chat Completions**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer <YOUR_ADMIN_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 100
  }'
```

**列出可用模型**：
```bash
curl https://api.enlyai.com/v1/models \
  -H "Authorization: Bearer <YOUR_ADMIN_API_KEY>"
```

**流式输出**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer <YOUR_ADMIN_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [{"role": "user", "content": "写一首诗"}],
    "stream": true
  }'
```

### 7.3 Python SDK 使用

```python
from openai import OpenAI

client = OpenAI(
    api_key="<YOUR_ADMIN_API_KEY>",
    base_url="https://api.enlyai.com/v1"
)

response = client.chat.completions.create(
    model="gemini-2.5-flash",
    messages=[{"role": "user", "content": "你好"}],
    max_tokens=100
)

print(response.choices[0].message.content)
```

### 7.4 Node.js SDK 使用

```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  apiKey: '<YOUR_ADMIN_API_KEY>',
  baseURL: 'https://api.enlyai.com/v1',
});

const response = await client.chat.completions.create({
  model: 'gemini-2.5-flash',
  messages: [{ role: 'user', content: '你好' }],
  max_tokens: 100,
});

console.log(response.choices[0].message.content);
```

### 7.5 兼容的客户端

| 客户端 | Base URL | 配置说明 |
|--------|----------|----------|
| Cherry Studio | https://api.enlyai.com/v1 | 设置 → 模型提供商 → OpenAI |
| Lobe Chat | https://api.enlyai.com/v1 | 设置 → 语言模型 → OpenAI |
| ChatBox | https://api.enlyai.com/v1 | 设置 → OpenAI API |
| NextChat | https://api.enlyai.com | 设置 → 接口配置 |
| Cursor | https://api.enlyai.com/v1 | Settings → Models → OpenAI API Key |
| Continue (VS Code) | https://api.enlyai.com/v1 | config.json → models |
| Cline (VS Code) | https://api.enlyai.com/v1 | 设置 → API Provider |

---

## 八、运维操作

### 8.1 Docker 管理

```bash
# 查看容器状态
docker ps

# 重启 New API
docker restart new-api

# 查看日志
docker logs new-api --tail 50

# New API 环境变量
# SQL_DSN=postgresql://newapi:<YOUR_DB_PASSWORD>@postgres:5432/newapi
# REDIS_CONN_STRING=redis://redis:6379
```

### 8.2 数据库操作

```bash
# 连接数据库
docker exec -it postgres psql -U newapi -d newapi

# 查看渠道
SELECT id, name, status, base_url FROM channels;

# 查看模型
SELECT DISTINCT model FROM abilities WHERE enabled=true ORDER BY model;

# 手动启用/禁用渠道
UPDATE channels SET status=1 WHERE name='渠道名';
UPDATE channels SET status=2 WHERE name='渠道名';
```

### 8.3 数据库备份

```bash
# 备份
docker exec postgres pg_dump -U newapi newapi > /root/backup_$(date +%Y%m%d).sql

# 恢复
docker exec -i postgres psql -U newapi newapi < /root/backup_20260609.sql
```

### 8.4 Nginx 管理

```bash
nginx -t          # 测试配置
nginx -s reload   # 重新加载
cat /etc/nginx/conf.d/api.enlyai.com.conf  # 查看配置
```

### 8.5 日志位置

| 日志 | 路径 |
|------|------|
| New API 日志 | `docker logs new-api` |
| Nginx 访问日志 | `/var/log/nginx/access.log` |
| Key 同步日志 | `/var/log/sync-free-keys.log` |

---

## 九、架构图

```
用户请求
    │
    ▼
┌─────────────────────────────────────────┐
│  Nginx (443/80)                         │
│  - SSL 终止 (Let's Encrypt)             │
│  - HTTP → HTTPS 重定向                   │
│  - 反向代理 + SSE 流式支持               │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  New API (localhost:3000)               │
│  - API Key 验证 & 路由                  │
│  - 渠道管理 & 负载均衡                   │
│  - 用户/令牌管理                         │
│  - Docker 网络: new-api_new-api-network │
└──────┬──────────────┬───────────────────┘
       │              │
       ▼              ▼
┌─────────────┐ ┌────────────────────────┐
│  PostgreSQL │ │  Redis                 │
│  (5432)     │ │  (6379)                │
│  数据存储    │ │  缓存/会话/Token验证    │
└─────────────┘ └────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  上游渠道 (Channels)                     │
│  ├─ free-llm-gateway (Railway)          │
│  └─ free-key-sync-* (aiapiv2.pekpik.com)│
└─────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  Key 来源                               │
│  └─ alistaitsacle/free-llm-api-keys     │
│     (Python 脚本自动同步，每30分钟)       │
└─────────────────────────────────────────┘
```

---

## 十、常见问题

### Q: 为什么有时 API 调用返回错误？
A: 免费 Key 有效期通常 24-48 小时，可能已失效。30 分钟同步一次会自动获取新 Key。如果持续失败，等待下一次同步即可。

### Q: 如何添加新的免费 Key 源？
A: 编辑 `/root/sync-free-keys.py`，在 `KEY_SOURCES` 列表中添加新仓库信息。

### Q: 首页显示"自用模式"吗？
A: 不显示。SelfUseModeEnabled 已关闭。

### Q: 用户可以自行注册吗？
A: 可以。访问 https://api.enlyai.com 点击注册即可，无需邮箱验证。

### Q: 模型广场显示多少个模型？
A: 动态展示，取决于当前有效的 Key 数量。abilities 表中有 34 个模型，/v1/models 显示 22 个。每 30 分钟自动刷新。

### Q: 如何限制某个用户只能用特定模型？
A: 为该用户创建专用令牌，在令牌上开启「模型限制」。

---

## 十一、安全注意事项

1. **管理员密码**：请定期修改 root 和 Lancer 的密码
2. **API Key 保护**：主 API Key 具有无限额度，请勿公开分享
3. **防火墙**：仅开放 22/80/443 端口
4. **SSL 证书**：自动续期，无需手动操作
5. **数据库备份**：建议定期备份 PostgreSQL 数据
6. **共享 Key 风险**：来自 GitHub 的共享 Key 可能被他人滥用或随时失效
