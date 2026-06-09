# API.ENLYAI.COM — New API 网关部署与使用文档

> 版本：v1.1 | 更新日期：2026-06-09 | New API 版本：v1.0.0-rc.10

---

## 一、系统概览

| 项目 | 详情 |
|------|------|
| 服务地址 | https://api.enlyai.com |
| 管理后台 | https://api.enlyai.com |
| API Base URL | `https://api.enlyai.com/v1` |
| New API 版本 | v1.0.0-rc.10 |
| 部署方式 | Docker Compose (PostgreSQL + Redis + New API) |
| SSL 证书 | Let's Encrypt，有效期至 2026-09-06，自动续期 |
| 服务器 | 阿里云 ECS (114.215.183.45) |

---

## 二、API Key 池配置

### 2.1 渠道（Channel）总览

| 状态 | 数量 | 说明 |
|------|------|------|
| 启用（status=1） | 2 | 正在提供服务的渠道 |
| 禁用（status=2） | 39 | 已失效或不可用的渠道 |
| **合计** | **41** | |

### 2.2 启用的渠道详情

| ID | 名称 | Base URL | 优先级 | 权重 | Key 前缀 | 支持模型数 |
|----|------|----------|--------|------|----------|-----------|
| 1 | free-llm-gateway | gateway-production-f831.up.railway.app | 10 | 10 | sk-free-llm-gat... | 15+ |
| 41 | free-llm-gateway-v2 | gateway-production-f831.up.railway.app | 15 | 15 | sk-free-llm-gat... | 4 |

### 2.3 禁用的渠道

- **free-key-1 ~ free-key-39**：来自 GitHub 共享仓库的 API Key，Base URL 为 `aiapiv2.pekpik.com`
- 禁用原因：这些 Key 已失效（上游返回 Invalid token），New API 自动检测后禁用

---

## 三、免费 Key 来源 — GitHub 仓库

### 3.1 当前已集成的 Key 源

| 仓库 | Stars | Key 格式 | Base URL | 采集方式 | 状态 |
|------|-------|----------|----------|----------|------|
| [alistaitsacle/free-llm-api-keys](https://github.com/alistaitsacle/free-llm-api-keys) | ~1,790 | `sk-` 前缀 | `aiapiv2.pekpik.com` | 自动脚本正则提取 | 已集成，39个Key已失效 |

### 3.2 可集成的更多免费 Key 源仓库

以下仓库提供免费 LLM API Key 或免费 API 端点，可按需集成：

#### 类型一：共享 API Key 仓库（直接提供 sk- 格式密钥）

| 仓库 | Stars | 说明 | Key 格式 | Base URL | 采集方式 |
|------|-------|------|----------|----------|----------|
| [alistaitsacle/free-llm-api-keys](https://github.com/alistaitsacle/free-llm-api-keys) | ~1,790 | 社区共享免费 Key，每日更新，有效期 24-48h | `sk-` 前缀 | `https://aiapiv2.pekpik.com/v1` | 正则 `sk-[a-zA-Z0-9_-]{10,}` 从 README.md 提取 |
| [FREE-openai-api-keys](https://github.com/atrcho7/FREE-openai-api-keys) | — | 免费 OpenAI Key 集合 | `sk-` 前缀 | `https://api.openai.com/v1` | 正则 `sk-[a-zA-Z0-9_-]{10,}` 从 README.md 提取 |

#### 类型二：免费 API 资源列表（提供免费端点信息，需自行注册获取 Key）

| 仓库 | Stars | 说明 | 免费额度 | 采集方式 |
|------|-------|------|----------|----------|
| [cheahjs/free-llm-api-resources](https://github.com/cheahjs/free-llm-api-resources) | 21,700+ | 最全的免费 LLM API 资源列表，自动验证端点可用性 | 各家不同 | 手动注册各家获取 Key |
| [mnfst/awesome-free-llm-apis](https://github.com/mnfst/awesome-free-llm-apis) | 热门 | 永久免费 LLM API 列表（Cohere、Gemini、Groq 等） | 各家不同 | 手动注册各家获取 Key |
| [tashfeenahmed/freellmapi](https://github.com/tashfeenahmed/freellmapi) | 6,200+ | 自托管 API 网关，聚合 16 家厂商免费额度，每月约 17 亿 Token | 聚合多厂商 | 部署为独立网关 |

#### 类型三：免费 API 提供商（需注册但免费）

| 提供商 | 免费额度 | Base URL | 支持模型 | 注册地址 |
|--------|----------|----------|----------|----------|
| Google AI Studio | 20次/天，250k tokens/分钟 | `https://generativelanguage.googleapis.com/v1beta` | Gemini 2.5 Flash, Gemini 3.x | [aistudio.google.com](https://aistudio.google.com/apikey) |
| Groq | 14,400次/天，6k tokens/分钟 | `https://api.groq.com/openai/v1` | Llama 3.3 70B, Llama 4, Qwen3 | [console.groq.com](https://console.groq.com) |
| Cerebras | 免费推理 | `https://api.cerebras.ai/v1` | Qwen3 235B | [cloud.cerebras.ai](https://cloud.cerebras.ai) |
| Cohere | 1,000次/月 | `https://api.cohere.com/v2` | Command A, Command R+ | [dashboard.cohere.com](https://dashboard.cohere.com/api-keys) |
| Mistral | 10亿 tokens/月 | `https://api.mistral.ai/v1` | Mistral Large 3, Medium 3.5 | [console.mistral.ai](https://console.mistral.ai) |
| OpenRouter | 20次/分钟，50次/天 | `https://openrouter.ai/api/v1` | 21个免费模型 | [openrouter.ai](https://openrouter.ai) |
| Cloudflare Workers AI | 10,000神经元/天 | `https://api.cloudflare.com/client/v4/accounts/{id}/ai` | 多种开源模型 | [dash.cloudflare.com](https://dash.cloudflare.com) |
| GitHub Models | 150次/天 | `https://models.github.ai/inference` | GPT-4o-mini 等 | [github.com](https://github.com/marketplace/models) |
| SambaNova | 免费推理 | `https://api.sambanova.ai/v1` | DeepSeek V3.x, Llama 4 | [cloud.sambanova.ai](https://cloud.sambanova.ai) |

### 3.3 Key 搜集方式详解

#### 自动搜集（适用于共享 Key 仓库）

**脚本位置**：`/root/sync-free-keys.sh`

**工作流程**：
1. 登录 New API 获取管理员 session
2. 从 GitHub 仓库的 README.md 下载原始内容（使用 raw.githubusercontent.com）
3. 使用正则表达式提取所有 API Key
4. 去重后与数据库中已有 Key 比对
5. 新增的 Key 通过 SQL 直接插入 channels 表
6. 已失效的 Key（test_time > 0 且 response_time = 0）自动禁用

**关键代码逻辑**：
```bash
# 从 GitHub 抓取 Key
GITHUB_KEYS=$(curl -sL "https://raw.githubusercontent.com/alistaitsacle/free-llm-api-keys/main/README.md" \
  | grep -oP 'sk-[a-zA-Z0-9_-]{10,}' | sort -u)

# 比对已有 Key，只添加新的
EXISTING_KEYS=$(docker exec postgres psql -U newapi -d newapi -t -A \
  -c "SELECT key FROM channels WHERE name LIKE 'free-key-%' AND status=1;")

for KEY in $GITHUB_KEYS; do
    if ! echo "$EXISTING_KEYS" | grep -q "$KEY"; then
        docker exec postgres psql -U newapi -d newapi -c "
        INSERT INTO channels (name, type, key, base_url, models, \"group\", priority, weight, status, test_time, created_time, auto_ban)
        VALUES ('free-key-sync-$NOW-$COUNT', 1, '$KEY', 'https://aiapiv2.pekpik.com', 'gpt-4o,gpt-4o-mini,gpt-3.5-turbo,deepseek-chat', 'default', 3, 3, 2, 0, $NOW, 1);"
    fi
done
```

**添加新的 Key 源仓库**：编辑 `/root/sync-free-keys.sh`，在脚本中添加新的 GitHub 仓库 URL 和对应的 Base URL：
```bash
# 示例：添加新的 Key 源
NEW_KEYS=$(curl -sL "https://raw.githubusercontent.com/用户名/仓库名/main/README.md" \
  | grep -oP 'sk-[a-zA-Z0-9_-]{10,}' | sort -u)

for KEY in $NEW_KEYS; do
    # 插入到 New API 渠道表
done
```

#### 手动搜集（适用于免费 API 提供商）

1. 访问提供商官网注册账号
2. 在控制台获取 API Key
3. 在 New API 管理后台 → 渠道管理 → 添加渠道
4. 填写 Base URL（不要包含 /v1）和 Key

---

## 四、模型配置

### 4.1 /v1/models 返回的模型（6个）

这些是 New API 内置了价格的模型，会出现在标准模型列表中：

| 模型 | 说明 |
|------|------|
| gpt-4o-mini | OpenAI GPT-4o Mini |
| gpt-4o | OpenAI GPT-4o |
| gpt-3.5-turbo | OpenAI GPT-3.5 Turbo |
| deepseek-chat | DeepSeek Chat |
| deepseek-coder | DeepSeek Coder |
| claude-3-haiku | Anthropic Claude 3 Haiku |

### 4.2 free-llm-gateway 支持的完整模型列表（26个）

由于开启了自用模式（SelfUseModeEnabled），以下模型虽然不在 /v1/models 列表中显示，但**均可直接调用**：

| 模型 | 类型 | 免费标识 |
|------|------|----------|
| gemini-2.5-flash | Google Gemini | |
| google/gemini-3.1-flash-lite | Google Gemini Lite | |
| claude-opus-4-7 | Anthropic Claude | |
| deepseek/deepseek-v4-flash | DeepSeek V4 Flash | |
| deepseek/deepseek-v4-pro | DeepSeek V4 Pro | |
| qwen/qwen3.6-flash | 通义千问 Flash | |
| qwen/qwen3.6-27b | 通义千问 27B | |
| qwen/qwen3.6-35b-a3b | 通义千问 35B | |
| qwen/qwen3.6-max-preview | 通义千问 Max | |
| qwen/qwen3.5-plus-20260420 | 通义千问 Plus | |
| mistralai/mistral-medium-3-5 | Mistral Medium | |
| ibm-granite/granite-4.1-8b | IBM Granite | |
| inclusionai/ring-2.6-1t | InclusionAI Ring | |
| openai/gpt-chat-latest | OpenAI GPT Latest | |
| openai/gpt-5.5 | OpenAI GPT-5.5 | |
| openai/gpt-5.5-pro | OpenAI GPT-5.5 Pro | |
| x-ai/grok-4.3 | xAI Grok | |
| kimi-k2.5 | Kimi K2.5 | |
| perceptron/perceptron-mk1 | Perceptron | |
| baidu/cobuddy:free | 百度 Cobuddy | 免费 |
| inclusionai/ling-2.6-1t:free | InclusionAI Ling | 免费 |
| inclusionai/ring-2.6-1t:free | InclusionAI Ring | 免费 |
| poolside/laguna-xs.2:free | Poolside Laguna XS | 免费 |
| poolside/laguna-m.1:free | Poolside Laguna M | 免费 |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free | NVIDIA Nemotron | 免费 |
| text-embedding-3-small | 文本嵌入模型 | |

### 4.3 已验证可用的模型

| 模型 | 测试结果 |
|------|----------|
| gemini-2.5-flash | 可用 |
| gpt-4o-mini | 可用（内置价格） |
| deepseek-chat | 可用（内置价格） |

### 4.4 添加更多免费提供商的模型

如需添加 Groq、Cerebras、Google AI Studio 等免费提供商的模型：

1. 注册对应提供商获取 API Key
2. 管理后台 → 渠道管理 → 添加渠道
3. 示例 — 添加 Groq：
   - 类型：OpenAI 兼容
   - 名称：groq-free
   - Base URL：`https://api.groq.com/openai`（不含 /v1）
   - Key：你的 Groq API Key
   - 模型：`llama-3.3-70b-versatile,llama-4-scout-17b,qwen3-32b`
4. 示例 — 添加 Google AI Studio：
   - 类型：Google Gemini
   - 名称：google-gemini-free
   - Base URL：`https://generativelanguage.googleapis.com`
   - Key：你的 Google API Key
   - 模型：`gemini-2.5-flash,gemini-3.1-flash-lite`

---

## 五、自动刷新与有效性检测

### 5.1 自动刷新频率

| 任务 | 频率 | 实现方式 |
|------|------|----------|
| GitHub 免费 Key 同步 | 每 30 分钟 | crontab: `*/30 * * * * /root/sync-free-keys.sh` |
| 渠道健康检测 | 每 30 分钟 | New API 内置: `ChannelUpdateFrequency=30` |
| SSL 证书续期 | 每天 3:00 | crontab: `0 3 * * * certbot renew --quiet --post-hook 'nginx -s reload'` |

### 5.2 Key 有效性自动检测

**New API 内置机制**：
- `AutomaticDisableChannelEnabled = true`：当渠道请求失败时，自动禁用该渠道
- `ChannelUpdateFrequency = 30`：每 30 分钟自动检测所有渠道的可用性
- 检测方式：向渠道发送测试请求，如果返回错误则标记为不可用
- 被禁用的渠道不会参与后续请求的路由分配
- `auto_ban = 1`：每个渠道都开启了自动封禁，连续失败后自动禁用

**同步脚本机制**：
- 每次同步时检查 `test_time > 0 AND response_time = 0` 的渠道并禁用
- 新增的 Key 默认状态为禁用（status=2），需要通过健康检测后才会启用

**alistaitsacle/free-llm-api-keys 的特殊性**：
- 该仓库的 Key 有效期通常为 24-48 小时
- 仓库每日多次批量更新，替换失效 Key
- 因此 30 分钟同步一次可以及时获取新 Key
- 但新 Key 也可能很快失效，这是共享 Key 的固有特性

### 5.3 同步日志

日志位置：`/var/log/sync-free-keys.log`

查看方式：
```bash
# 查看最近的同步记录
tail -20 /var/log/sync-free-keys.log

# 查看所有同步记录
cat /var/log/sync-free-keys.log

# 搜索特定时间的记录
grep "2026-06-09" /var/log/sync-free-keys.log
```

### 5.4 手动触发同步

```bash
# 立即执行一次 Key 同步
bash /root/sync-free-keys.sh

# 查看同步结果
tail -5 /var/log/sync-free-keys.log
```

---

## 六、管理员操作指南

### 6.1 登录管理后台

1. 访问 https://api.enlyai.com
2. 使用管理员账号登录：
   - 用户名：`root`
   - 密码：`Enlyai2026!`
3. 另一个管理员账号：
   - 用户名：`Lancer`
   - 角色：管理员（role=100）

### 6.2 渠道管理（Channel Management）

**查看渠道**：
- 左侧菜单 → 渠道管理 → 查看所有渠道列表
- 可以按状态筛选（启用/禁用/全部）

**添加渠道**：
1. 点击「添加新的渠道」
2. 填写信息：
   - **类型**：选择 API 提供商类型（1 = OpenAI 兼容）
   - **名称**：给渠道起名
   - **Base URL**：API 端点地址（**不要包含 /v1**，New API 会自动添加）
   - **密钥**：API Key
   - **模型**：逗号分隔的模型名称列表
   - **分组**：default
   - **优先级**：数字越大越优先
   - **权重**：负载均衡权重
3. 保存

**测试渠道**：
- 在渠道列表中点击「测试」按钮
- New API 会向该渠道发送测试请求验证可用性

**禁用/启用渠道**：
- 点击渠道状态开关即可切换

**批量操作**：
- 由于当前版本（v1.0.0-rc.10）的渠道添加 API 存在 panic bug
- 批量添加渠道建议通过数据库直接操作：
```bash
docker exec postgres psql -U newapi -d newapi -c "
INSERT INTO channels (name, type, key, base_url, models, \"group\", priority, weight, status, test_time, created_time, auto_ban)
VALUES ('渠道名', 1, 'sk-xxx', 'https://api.example.com', 'model1,model2', 'default', 10, 10, 1, 0, EXTRACT(EPOCH FROM NOW())::bigint, 1);
"
```

### 6.3 令牌管理（Token Management）

令牌是用户调用 API 的凭证。

**查看令牌**：
- 左侧菜单 → 令牌管理

**当前令牌**：

| 名称 | Key | 额度 | 有效期 |
|------|-----|------|--------|
| enlyai-main-key | dpkbeRCTi7wQTMpct5cwJ5fkc7w9nKAdhdx8IeFBCldo7QZW | 无限 | 永久 |
| enlyai-public-key | onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ | 无限 | 永久 |

> 注意：使用时需要加 `sk-` 前缀，即 `sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ`

**创建新令牌**：
1. 点击「添加新的令牌」
2. 设置参数：
   - **名称**：令牌名称
   - **额度**：设置使用额度（0 = 使用用户额度）
   - **无限额度**：勾选则不限制
   - **过期时间**：-1 表示永不过期，或设置具体时间戳
   - **模型限制**：可限制该令牌只能使用特定模型
   - **分组**：default

**限制令牌只能使用某些模型**：
1. 编辑令牌
2. 开启「模型限制」
3. 输入允许的模型名称（逗号分隔），例如：`gemini-2.5-flash,qwen/qwen3.6-flash`
4. 保存后，使用该令牌的请求只能调用指定的模型

**设置令牌有效期**：
1. 编辑令牌
2. 在「过期时间」字段设置 Unix 时间戳
3. 常用时间戳计算：
```bash
# 1天后过期
echo $(($(date +%s) + 86400))

# 7天后过期
echo $(($(date +%s) + 604800))

# 30天后过期
echo $(($(date +%s) + 2592000))

# 永不过期
-1
```

### 6.4 用户管理（User Management）

**查看用户**：
- 左侧菜单 → 用户管理

**当前用户**：

| 用户名 | 角色 | 额度 | 已用 |
|--------|------|------|------|
| root | 管理员(100) | 无限 | 226 |
| Lancer | 管理员(100) | 无限 | 0 |
| admin | 普通用户(1) | 0 | 0 |

**限制用户只能使用某些模型**：

方法一：通过令牌限制（推荐）
1. 为用户创建专用令牌
2. 在令牌上设置模型限制
3. 用户只能使用该令牌允许的模型

方法二：通过分组限制
1. 创建新的用户分组（如 "basic"、"premium"）
2. 在渠道设置中指定哪些分组可以访问
3. 将用户分配到对应分组
4. 示例：创建 "basic" 分组只能访问免费模型，"premium" 分组可访问所有模型

方法三：通过数据库操作
```bash
# 修改用户分组
docker exec postgres psql -U newapi -d newapi -c \
  "UPDATE users SET \"group\"='basic' WHERE username='某用户';"

# 创建限制模型的令牌（在管理后台操作更方便）
```

**设置新用户默认额度**：
- 系统设置 → 运营设置 → QuotaForNewUser
- 当前值：500000000（约 $1000 等值）

**封禁/解封用户**：
- 用户管理 → 编辑用户 → 状态：1=正常，2=封禁

**设置用户 API Key 有效期**：
- 为用户创建令牌时设置过期时间
- 或编辑已有令牌修改过期时间
- 过期后令牌自动失效，用户需要重新获取

### 6.5 系统设置（System Settings）

**当前关键配置**：

| 设置项 | 当前值 | 说明 |
|--------|--------|------|
| ServerAddress | https://api.enlyai.com | 服务器地址 |
| SelfUseModeEnabled | true | 自用模式，无需配置模型价格 |
| ChannelUpdateFrequency | 30 | 渠道检测频率（分钟） |
| AutomaticDisableChannelEnabled | true | 自动禁用失效渠道 |
| QuotaForNewUser | 500000000 | 新用户默认额度 |
| RegisterEnabled | true | 允许用户注册 |
| PasswordRegisterEnabled | true | 允许密码注册 |
| GroupRatio | {"default":1} | 分组倍率 |

**修改系统设置**：
1. 左侧菜单 → 系统设置
2. 修改对应配置项
3. 点击保存

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
sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ
```

### 7.2 cURL 调用示例

**Chat Completions**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ" \
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
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ"
```

**文本嵌入**：
```bash
curl https://api.enlyai.com/v1/embeddings \
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "Hello world"
  }'
```

**流式输出**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [{"role": "user", "content": "写一首诗"}],
    "stream": true
  }'
```

**多轮对话**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [
      {"role": "system", "content": "你是一个有帮助的助手"},
      {"role": "user", "content": "什么是量子计算？"},
      {"role": "assistant", "content": "量子计算是利用量子力学原理..."},
      {"role": "user", "content": "能举个例子吗？"}
    ]
  }'
```

**Function Calling（工具调用）**：
```bash
curl https://api.enlyai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini-2.5-flash",
    "messages": [{"role": "user", "content": "北京今天天气怎么样？"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "获取指定城市的天气",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string", "description": "城市名"}
          },
          "required": ["city"]
        }
      }
    }]
  }'
```

### 7.3 Python SDK 使用

**基础调用**：
```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ",
    base_url="https://api.enlyai.com/v1"
)

response = client.chat.completions.create(
    model="gemini-2.5-flash",
    messages=[{"role": "user", "content": "你好"}],
    max_tokens=100
)

print(response.choices[0].message.content)
```

**流式输出**：
```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ",
    base_url="https://api.enlyai.com/v1"
)

stream = client.chat.completions.create(
    model="gemini-2.5-flash",
    messages=[{"role": "user", "content": "写一首诗"}],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

**文本嵌入**：
```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ",
    base_url="https://api.enlyai.com/v1"
)

response = client.embeddings.create(
    model="text-embedding-3-small",
    input="Hello world"
)

print(response.data[0].embedding[:5])  # 打印前5维
```

**异步调用**：
```python
import asyncio
from openai import AsyncOpenAI

async def main():
    client = AsyncOpenAI(
        api_key="sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ",
        base_url="https://api.enlyai.com/v1"
    )

    response = await client.chat.completions.create(
        model="gemini-2.5-flash",
        messages=[{"role": "user", "content": "你好"}],
        max_tokens=100
    )

    print(response.choices[0].message.content)

asyncio.run(main())
```

### 7.4 Node.js SDK 使用

```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  apiKey: 'sk-onYGKMoS2VBQyyW47qh46Z1yJAVRPrAdnNMzM7i9n4NhF8qJ',
  baseURL: 'https://api.enlyai.com/v1',
});

async function main() {
  const stream = await client.chat.completions.create({
    model: 'gemini-2.5-flash',
    messages: [{ role: 'user', content: '你好' }],
    stream: true,
  });

  for await (const chunk of stream) {
    process.stdout.write(chunk.choices[0]?.delta?.content || '');
  }
}

main();
```

### 7.5 错误码说明

| HTTP 状态码 | 含义 | 处理建议 |
|-------------|------|----------|
| 200 | 成功 | — |
| 400 | 请求参数错误 | 检查请求体格式 |
| 401 | API Key 无效 | 检查 Key 是否正确，是否已过期 |
| 403 | 额度不足 | 检查用户/令牌额度 |
| 404 | 模型不存在 | 检查模型名称是否正确 |
| 429 | 请求频率超限 | 降低请求频率，添加重试逻辑 |
| 500 | 服务器内部错误 | 稍后重试 |
| 502 | 上游渠道不可用 | 所有渠道都已失效，等待自动恢复 |

**错误响应格式**：
```json
{
  "error": {
    "message": "错误描述",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

### 7.6 兼容的客户端

New API 兼容 OpenAI API 格式，可直接配置以下客户端：

| 客户端 | Base URL | API Key | 配置说明 |
|--------|----------|---------|----------|
| Cherry Studio | https://api.enlyai.com/v1 | sk-xxx | 设置 → 模型提供商 → OpenAI |
| Lobe Chat | https://api.enlyai.com/v1 | sk-xxx | 设置 → 语言模型 → OpenAI |
| DeepChat | https://api.enlyai.com/v1 | sk-xxx | 设置 → API 配置 |
| OpenCat | https://api.enlyai.com | sk-xxx | 设置 → 自定义 API |
| ChatBox | https://api.enlyai.com/v1 | sk-xxx | 设置 → OpenAI API |
| NextChat | https://api.enlyai.com | sk-xxx | 设置 → 接口配置 |
| Cursor | https://api.enlyai.com/v1 | sk-xxx | Settings → Models → OpenAI API Key |
| Continue (VS Code) | https://api.enlyai.com/v1 | sk-xxx | config.json → models |
| Cline (VS Code) | https://api.enlyai.com/v1 | sk-xxx | 设置 → API Provider |

---

## 八、运维操作

### 8.1 服务器 SSH 登录

```bash
ssh root@114.215.183.45
# 密码：!freeworkLVooJo2
```

### 8.2 Docker 管理

```bash
# 查看容器状态
docker ps

# 重启 New API
docker restart new-api

# 查看日志
docker logs new-api --tail 50

# 实时查看日志
docker logs new-api -f

# 重启所有服务
cd /root && docker compose -f docker-compose.prod.yml restart

# 停止所有服务
cd /root && docker compose -f docker-compose.prod.yml down

# 启动所有服务
cd /root && docker compose -f docker-compose.prod.yml up -d
```

### 8.3 数据库操作

```bash
# 连接数据库
docker exec -it postgres psql -U newapi -d newapi

# 查看渠道
SELECT id, name, status, base_url FROM channels;

# 查看令牌
SELECT id, name, key, status FROM tokens WHERE deleted_at IS NULL;

# 查看用户
SELECT id, username, role, quota FROM users WHERE deleted_at IS NULL;

# 手动禁用渠道
UPDATE channels SET status=2 WHERE name='渠道名';

# 手动启用渠道
UPDATE channels SET status=1 WHERE name='渠道名';

# 修改用户额度
UPDATE users SET quota=999999999999 WHERE username='用户名';

# 查看渠道测试结果
SELECT id, name, status, test_time, response_time FROM channels ORDER BY id;
```

### 8.4 数据库备份与恢复

```bash
# 备份数据库
docker exec postgres pg_dump -U newapi newapi > /root/backup_$(date +%Y%m%d_%H%M%S).sql

# 恢复数据库
docker exec -i postgres psql -U newapi newapi < /root/backup_20260609.sql

# 设置自动备份（每天 2:00）
(crontab -l 2>/dev/null; echo "0 2 * * * docker exec postgres pg_dump -U newapi newapi > /root/backup_\$(date +\%Y\%m\%d).sql") | crontab -

# 清理 7 天前的备份
(crontab -l 2>/dev/null; echo "0 3 * * * find /root -name 'backup_*.sql' -mtime +7 -delete") | crontab -
```

### 8.5 Nginx 管理

```bash
# 测试配置
nginx -t

# 重新加载配置
nginx -s reload

# 重启 Nginx
killall nginx && nginx

# 查看配置
cat /etc/nginx/conf.d/api.enlyai.com.conf

# 查看 Nginx 状态
systemctl status nginx
```

### 8.6 SSL 证书管理

```bash
# 查看证书信息
certbot certificates

# 手动续期
certbot renew

# 强制续期
certbot renew --force-renewal

# 续期后重载 Nginx
certbot renew --post-hook 'nginx -s reload'
```

### 8.7 防火墙管理

```bash
# 查看规则
iptables -L INPUT -n

# 开放端口
iptables -A INPUT -p tcp --dport 端口号 -j ACCEPT

# 保存规则
service iptables save

# 查看当前开放的端口
iptables -L INPUT -n | grep ACCEPT
```

### 8.8 监控与告警

**查看渠道健康状态**：
```bash
# 通过 API 查看渠道状态
LOGIN_RESP=$(curl -s -c /tmp/cookies http://localhost:3000/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"username":"root","password":"Enlyai2026!"}')
USER_ID=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('id',1))")

curl -s -b /tmp/cookies -H "New-Api-User: $USER_ID" \
  "http://localhost:3000/api/channel/?p=0&page_size=100" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for c in d.get('data',{}).get('items',[]):
    status = '启用' if c.get('status') == 1 else '禁用'
    print(f'{c[\"id\"]:3d} | {c[\"name\"]:30s} | {status} | {c.get(\"test_time\",0)} | {c.get(\"response_time\",0)}ms')
"
```

**设置 Key 失效告警**（可选，需配置 Webhook）：
```bash
# 创建告警脚本
cat > /root/alert.sh << 'EOF'
#!/bin/bash
# 检查是否有渠道被禁用
DISABLED=$(docker exec postgres psql -U newapi -d newapi -t -A \
  -c "SELECT COUNT(*) FROM channels WHERE status=2 AND name LIKE 'free-key-%';")

if [ "$DISABLED" -gt 30 ]; then
    # 发送告警（替换为你的 Webhook URL）
    curl -s -X POST "你的Webhook URL" \
      -H "Content-Type: application/json" \
      -d "{\"content\":\"警告：$DISABLED 个免费 Key 渠道已禁用\"}"
fi
EOF
chmod +x /root/alert.sh

# 添加到 crontab（每小时检查一次）
(crontab -l 2>/dev/null; echo "0 * * * * /root/alert.sh") | crontab -
```

### 8.9 日志位置

| 日志 | 路径 |
|------|------|
| New API 日志 | `docker logs new-api` |
| Nginx 访问日志 | `/var/log/nginx/access.log` |
| Nginx 错误日志 | `/var/log/nginx/error.log` |
| Key 同步日志 | `/var/log/sync-free-keys.log` |
| SSL 续期日志 | `/var/log/letsencrypt/letsencrypt.log` |

---

## 九、架构图

```
用户请求
    │
    ▼
┌─────────────────────────────────────────┐
│  Nginx (443/80)                         │
│  - SSL 终止                             │
│  - HTTP → HTTPS 重定向                   │
│  - 反向代理 + SSE 流式支持               │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  New API (localhost:3000)               │
│  - API Key 验证 & 路由                  │
│  - 渠道管理 & 负载均衡                   │
│  - 自动禁用失效渠道                      │
│  - 用户/令牌管理                         │
└──────┬──────────────┬───────────────────┘
       │              │
       ▼              ▼
┌─────────────┐ ┌────────────────────────┐
│  PostgreSQL │ │  Redis                 │
│  (数据存储)  │ │  (缓存/会话)           │
└─────────────┘ └────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  上游渠道 (Channels)                     │
│  ├─ free-llm-gateway (Railway)  优先级10│
│  ├─ free-llm-gateway-v2         优先级15│
│  └─ free-key-1~39 (已禁用)              │
└─────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│  Key 来源                               │
│  ├─ alistaitsacle/free-llm-api-keys     │
│  │  (自动同步，每30分钟)                  │
│  └─ 免费API提供商（可手动添加）           │
│     ├─ Google AI Studio (Gemini)        │
│     ├─ Groq (Llama/Qwen)               │
│     ├─ Cerebras (Qwen3 235B)           │
│     ├─ Cohere (Command A)              │
│     ├─ Mistral (Large 3)               │
│     ├─ OpenRouter (21个免费模型)         │
│     └─ Cloudflare Workers AI            │
└─────────────────────────────────────────┘
```

---

## 十、常见问题

### Q: 为什么 /v1/models 只显示 6 个模型？
A: /v1/models 端点只返回 New API 内置了价格的模型。由于开启了自用模式（SelfUseModeEnabled），所有渠道中配置的模型都可以直接调用，即使不在列表中显示。

### Q: 如何添加新的免费 Key 源？
A: 两种方式：
1. **自动**：修改 `/root/sync-free-keys.sh`，添加新的 GitHub 仓库 URL 和对应 Base URL
2. **手动**：管理后台 → 渠道管理 → 添加渠道，填写免费 API 提供商的 Key 和 Base URL

### Q: 渠道被自动禁用了怎么办？
A: New API 会在渠道连续请求失败时自动禁用。修复上游问题后，在管理后台手动启用即可。对于共享 Key 仓库的 Key，30 分钟同步一次会自动获取新 Key。

### Q: 如何限制某个用户只能用特定模型？
A: 为该用户创建专用令牌，在令牌上开启「模型限制」，指定允许的模型列表。

### Q: 如何设置 API Key 的有效期？
A: 编辑令牌，在「过期时间」字段设置 Unix 时间戳。-1 表示永不过期。

### Q: 如何查看 API 使用量？
A: 管理后台 → 日志 → 查看使用记录。可按用户、令牌、模型、渠道筛选。

### Q: 免费 Key 经常失效怎么办？
A: 这是共享 Key 的固有特性。alistaitsacle/free-llm-api-keys 仓库的 Key 有效期通常 24-48 小时，30 分钟同步一次可以及时获取新 Key。建议同时添加多个免费 API 提供商（如 Groq、Google AI Studio）作为备用渠道。

### Q: 如何添加 Groq 等免费提供商？
A: 参见本文档 4.4 节「添加更多免费提供商的模型」。注册对应提供商 → 获取 API Key → 在管理后台添加渠道。

---

## 十一、安全注意事项

1. **管理员密码**：请定期修改 root 和 Lancer 的密码
2. **API Key 保护**：主 API Key 具有无限额度，请勿公开分享
3. **防火墙**：仅开放 22/80/443/3000 端口
4. **SSL 证书**：自动续期，无需手动操作
5. **数据库备份**：建议定期备份 PostgreSQL 数据
   ```bash
   docker exec postgres pg_dump -U newapi newapi > /root/backup_$(date +%Y%m%d).sql
   ```
6. **共享 Key 风险**：来自 GitHub 的共享 Key 可能被他人滥用或随时失效，不建议用于生产环境
7. **速率限制**：建议在 Nginx 层配置速率限制，防止单个用户过度消耗资源
   ```nginx
   # 在 nginx 配置中添加
   limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
   location /v1/ {
       limit_req zone=api burst=10 nodelay;
       proxy_pass http://new_api;
   }
   ```
