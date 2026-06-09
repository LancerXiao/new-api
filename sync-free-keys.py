#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自动从 GitHub 免费 API Key 仓库抓取 Key 并导入 New API
唯一来源: https://github.com/alistaitsacle/free-llm-api-keys
每30分钟由 crontab 执行

统一模型名称:
  - enlyai-chat: 自动路由到额度最高的聊天模型
  - enlyai-embedding: 自动路由到嵌入模型
"""

import re
import os
import json
import time
import subprocess
import urllib.request
import urllib.error
from datetime import datetime

try:
    import ssl
    SSL_CONTEXT = ssl.create_default_context()
except:
    SSL_CONTEXT = None

# ============ 配置 ============
KEY_SOURCES = [
    {
        "repo": "alistaitsacle/free-llm-api-keys",
        "file": "README.md",
        "branch": "main"
    }
]
BACKEND_BASE_URL = "https://aiapiv2.pekpik.com"
PSQL_CMD = ["docker", "exec", "postgres", "psql", "-U", "newapi", "-d", "newapi", "-t", "-A"]
LOG_FILE = "/var/log/sync-free-keys.log"

# 模型能力分级（priority 越高越优先选择）
# 格式: (模型名模式, priority)
# Tier 1 (priority=10): 顶级模型 - GPT-5.5, Claude Opus, Grok
# Tier 2 (priority=7): 高级模型 - Gemini 2.5 Flash, DeepSeek V4 Pro, Qwen Max
# Tier 3 (priority=5): 中级模型 - Qwen 27B/35B, Kimi, Mistral, DeepSeek Flash
# Tier 4 (priority=3): 入级模型 - 小模型, 开源模型
# Tier 5 (priority=1): 免费模型 - :free 后缀
MODEL_TIERS = [
    # Tier 1: 顶级模型
    ("gpt-5.5-pro", 10),
    ("openai/gpt-5.5-pro", 10),
    ("gpt-5.5", 10),
    ("openai/gpt-5.5", 10),
    ("claude-opus-4-7", 10),
    ("x-ai/grok-4.3", 10),
    # Tier 2: 高级模型
    ("gemini-2.5-flash", 7),
    ("deepseek/deepseek-v4-pro", 7),
    ("deepseek-v4-pro", 7),
    ("qwen/qwen3.6-max-preview", 7),
    ("qwen3.6-max-preview", 7),
    ("kimi-k2.5", 7),
    ("mistralai/mistral-medium-3-5", 7),
    ("openai/gpt-chat-latest", 7),
    ("gpt-chat-latest", 7),
    # Tier 3: 中级模型
    ("deepseek/deepseek-v4-flash", 5),
    ("deepseek-v4-flash", 5),
    ("qwen/qwen3.6-35b-a3b", 5),
    ("qwen/qwen3.6-27b", 5),
    ("qwen/qwen3.6-flash", 5),
    ("qwen3.6-flash", 5),
    ("qwen/qwen3.5-plus-20260420", 5),
    ("google/gemini-3.1-flash-lite", 5),
    ("gemini-3.1-flash-lite", 5),
    ("inclusionai/ring-2.6-1t", 5),
    ("perceptron/perceptron-mk1", 5),
    # Tier 4: 入级模型
    ("ibm-granite/granite-4.1-8b", 3),
    ("openrouter/owl-alpha", 3),
    # Tier 5: 免费模型
    ("poolside/laguna-xs.2:free", 1),
    ("poolside/laguna-m.1:free", 1),
    ("inclusionai/ling-2.6-1t:free", 1),
    ("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", 1),
    ("baidu/cobuddy:free", 1),
]

# 统一模型名称映射
UNIFIED_MODELS = {
    "enlyai-chat": [
        "gpt-5.5", "gpt-5.5-pro", "gpt-chat-latest",
        "claude-opus-4-7",
        "gemini-2.5-flash", "gemini-3.1-flash-lite",
        "deepseek-v4-pro", "deepseek-v4-flash",
        "qwen/qwen3.6-max-preview", "qwen/qwen3.6-flash",
        "qwen/qwen3.6-27b", "qwen/qwen3.6-35b-a3b",
        "kimi-k2.5",
        "mistralai/mistral-medium-3-5",
        "x-ai/grok-4.3",
        "openai/gpt-5.5", "openai/gpt-5.5-pro", "openai/gpt-chat-latest",
        "deepseek/deepseek-v4-pro", "deepseek/deepseek-v4-flash",
        "google/gemini-3.1-flash-lite",
        "inclusionai/ring-2.6-1t",
        "perceptron/perceptron-mk1",
        "ibm-granite/granite-4.1-8b",
        "qwen/qwen3.5-plus-20260420",
        "openrouter/owl-alpha",
        # free models (lower priority)
        "poolside/laguna-xs.2:free", "poolside/laguna-m.1:free",
        "inclusionai/ling-2.6-1t:free",
        "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
        "baidu/cobuddy:free",
    ],
    "enlyai-embedding": [
        "text-embedding-3-small",
    ]
}

# 聊天模型判定：排除嵌入模型
CHAT_MODEL_EXCLUDE = ["text-embedding-3-small", "embedding"]
# ============ 配置结束 ============


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = "[%s] %s" % (ts, msg)
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except:
        pass


def psql_exec(sql):
    try:
        result = subprocess.run(
            PSQL_CMD + ["-c", sql],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30
        )
        out = result.stdout.decode("utf-8", errors="replace").strip()
        err = result.stderr.decode("utf-8", errors="replace").strip()
        if err and "ERROR" in err.upper():
            log("  SQL ERROR: %s" % err[:200])
            return ""
        return out
    except Exception as e:
        log("  SQL exception: %s" % str(e))
        return ""


def psql_exec_silent(sql):
    try:
        result = subprocess.run(
            PSQL_CMD + ["-c", sql],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30
        )
        return result.returncode == 0
    except:
        return False


def fetch_readme(repo, filepath, branch):
    content = None

    # Method 1: GitHub API
    url = "https://api.github.com/repos/%s/contents/%s" % (repo, filepath)
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github.v3.raw",
        "User-Agent": "sync-free-keys/1.0"
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            content = resp.read().decode("utf-8")
        if content and "sk-" in content:
            log("  GitHub API 获取成功 (%d bytes)" % len(content))
            return content
    except Exception as e:
        log("  GitHub API 失败: %s" % str(e)[:100])

    # Method 2: Raw URL
    url = "https://raw.githubusercontent.com/%s/%s/%s" % (repo, branch, filepath)
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            content = resp.read().decode("utf-8")
        if content and "sk-" in content:
            log("  Raw URL 获取成功 (%d bytes)" % len(content))
            return content
    except Exception as e:
        log("  Raw URL 失败: %s" % str(e)[:100])

    # Method 3: git clone
    try:
        tmp_dir = "/tmp/free-keys-%d" % int(time.time())
        subprocess.run(
            ["git", "clone", "--depth", "1", "https://github.com/%s.git" % repo, tmp_dir],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
        )
        filepath_full = os.path.join(tmp_dir, filepath)
        with open(filepath_full, "r") as f:
            content = f.read()
        subprocess.run(["rm", "-rf", tmp_dir], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if content and "sk-" in content:
            log("  git clone 获取成功 (%d bytes)" % len(content))
            return content
    except Exception as e:
        log("  git clone 失败: %s" % str(e)[:100])

    return None


def extract_key_model_pairs(content):
    pairs = re.findall(
        r'\| `sk-([a-zA-Z0-9_-]+)` \| ([a-zA-Z0-9_/.:-]+) \|',
        content
    )
    return [("sk-%s" % key, model) for key, model in pairs]


def is_chat_model(model):
    """Check if model is a chat model (not embedding)"""
    for exc in CHAT_MODEL_EXCLUDE:
        if exc in model.lower():
            return False
    return True


def get_unified_models_for(actual_model):
    """Get which unified model names this actual model should map to"""
    result = []
    for unified, patterns in UNIFIED_MODELS.items():
        for pattern in patterns:
            if actual_model == pattern or actual_model.endswith(pattern):
                result.append(unified)
                break
    # If it's a chat model not in any unified list, add to enlyai-chat
    if is_chat_model(actual_model) and "enlyai-chat" not in result:
        result.append("enlyai-chat")
    return result


def cleanup_all_channels():
    log("清理所有渠道和 abilities 记录...")
    psql_exec("DELETE FROM abilities;")
    psql_exec("DELETE FROM channels;")
    psql_exec("ALTER SEQUENCE IF EXISTS channels_id_seq RESTART WITH 1;")
    log("清理完成")


def get_model_priority(model):
    """根据模型能力分级返回 priority"""
    for pattern, priority in MODEL_TIERS:
        if model == pattern or model.endswith(pattern):
            return priority
    # 免费模型
    if ":free" in model:
        return 1
    # 嵌入模型
    if "embedding" in model:
        return 5
    # 未知模型默认中级
    return 5


def add_channel_with_abilities(key, model, channel_id):
    ts = int(time.time())
    channel_name = "free-key-sync-%d-%d" % (ts, channel_id)

    # Determine unified models this channel should support
    unified = get_unified_models_for(model)

    # Build models list: actual model + unified model names
    models_list = [model] + unified
    models_str = ",".join(models_list)

    # Build model_mapping: unified -> actual
    mapping = {}
    for u in unified:
        mapping[u] = model
    mapping_str = json.dumps(mapping) if mapping else ""

    # Escape single quotes for SQL
    mapping_sql = mapping_str.replace("'", "''")

    # Get priority based on model capability
    priority = get_model_priority(model)
    # Weight = priority (higher priority also gets more weight)
    weight = priority

    ok = psql_exec_silent(
        'INSERT INTO channels (id, name, type, key, base_url, models, model_mapping, "group", status, priority, weight, auto_ban, test_time, created_time) '
        "VALUES (%d, '%s', 1, '%s', '%s', '%s', '%s', 'default', 1, %d, %d, 0, 0, %d);" % (
            channel_id, channel_name, key, BACKEND_BASE_URL, models_str, mapping_sql, priority, weight, ts
        )
    )

    if ok:
        # Add abilities for each model (actual + unified)
        for m in models_list:
            psql_exec_silent(
                'INSERT INTO abilities ("group", model, channel_id, enabled, priority, weight) '
                "VALUES ('default', '%s', %d, true, %d, %d);" % (m, channel_id, priority, weight)
            )
        log("  渠道 #%d: %s (P%d) -> %s" % (channel_id, model, priority, "+".join(unified) if unified else "no-unified"))
        return True
    else:
        log("  渠道失败: %s" % channel_name)
        return False


def test_channel_upstream(key, model, timeout=15):
    """测试单个上游渠道是否可用，返回 (ok, error_msg)
    使用 curl 而非 urllib，因为上游会拒绝 Python 默认 User-Agent"""
    is_embedding = "embedding" in model.lower()

    if is_embedding:
        url = "%s/v1/embeddings" % BACKEND_BASE_URL
        payload = json.dumps({"model": model, "input": "test"})
    else:
        url = "%s/v1/chat/completions" % BACKEND_BASE_URL
        # 注意：gpt-5.5 要求 max_tokens >= 16
        payload = json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": "Hi"}],
            "max_tokens": 20
        })

    try:
        result = subprocess.run(
            ["curl", "-s", "--max-time", str(timeout), url,
             "-H", "Authorization: Bearer %s" % key,
             "-H", "Content-Type: application/json",
             "-d", payload],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=timeout + 5
        )
        body = result.stdout.decode("utf-8", errors="replace").strip()
    except Exception as e:
        return (False, str(e)[:100])

    if not body:
        return (False, "empty_response")

    try:
        data = json.loads(body)
    except:
        return (False, body[:80])

    if is_embedding:
        if "data" in data and len(data.get("data", [])) > 0 and "embedding" in data["data"][0]:
            return (True, "")
    else:
        if "choices" in data and len(data.get("choices", [])) > 0:
            return (True, "")

    err_msg = data.get("error", {}).get("message", "no_content")[:100]
    return (False, err_msg)


def test_and_disable_dead_channels(pairs):
    """测试所有渠道，禁用不可用的渠道。返回 (active_count, disabled_count)"""
    log("开始测试渠道可用性...")

    # 获取所有活跃渠道
    channels_str = psql_exec("SELECT id, key, models FROM channels WHERE status=1 ORDER BY id;")
    if not channels_str:
        log("没有活跃渠道需要测试")
        return (0, 0)

    active = 0
    disabled = 0

    for line in channels_str.split("\n"):
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 3:
            continue

        ch_id = parts[0].strip()
        ch_key = parts[1].strip()
        ch_models = parts[2].strip()

        # 取第一个模型（实际模型名，不是统一模型名）
        model_list = [m.strip() for m in ch_models.split(",")]
        actual_model = model_list[0]  # 第一个是实际模型

        ok, err = test_channel_upstream(ch_key, actual_model)

        if ok:
            active += 1
            log("  渠道 #%s %s: 可用" % (ch_id, actual_model))
        else:
            disabled += 1
            log("  渠道 #%s %s: 不可用 (%s) -> 禁用" % (ch_id, actual_model, err[:60]))
            psql_exec("UPDATE channels SET status=2 WHERE id=%s;" % ch_id)
            # 同时禁用对应的 abilities
            psql_exec("DELETE FROM abilities WHERE channel_id=%s;" % ch_id)

    log("渠道测试完成: %d 可用, %d 禁用" % (active, disabled))
    return (active, disabled)


def main():
    log("=" * 55)
    log("同步免费 API Key (唯一来源: alistaitsacle/free-llm-api-keys)")
    log("统一模型: enlyai-chat (聊天), enlyai-embedding (嵌入)")
    log("=" * 55)

    # 1. Fetch key-model pairs
    all_pairs = []
    for source in KEY_SOURCES:
        content = fetch_readme(source["repo"], source["file"], source["branch"])
        if content:
            pairs = extract_key_model_pairs(content)
            log("  从 %s 提取了 %d 个 Key-Model 对" % (source["repo"], len(pairs)))
            all_pairs.extend(pairs)

    if not all_pairs:
        log("未获取到 Key，保留现有渠道")
        return

    # 2. Deduplicate
    seen = set()
    unique_pairs = []
    for key, model in all_pairs:
        if key not in seen:
            seen.add(key)
            unique_pairs.append((key, model))

    log("共 %d 个唯一 Key-Model 对" % len(unique_pairs))

    # 3. Clean up
    cleanup_all_channels()

    # 4. Add channels with unified model mapping
    next_id = 1
    added = 0
    for key, model in unique_pairs:
        if add_channel_with_abilities(key, model, next_id):
            added += 1
        next_id += 1

    # 5. Ensure auto_ban=0
    psql_exec("UPDATE channels SET auto_ban=0;")

    # 6. Test channels and disable dead ones
    active, dead = test_and_disable_dead_channels(unique_pairs)

    # 7. Verify
    ch_count = psql_exec("SELECT COUNT(*) FROM channels WHERE status=1;")
    model_count = psql_exec("SELECT COUNT(DISTINCT model) FROM abilities WHERE enabled=true;")
    unified_count = psql_exec("SELECT COUNT(DISTINCT model) FROM abilities WHERE enabled=true AND model LIKE 'enlyai-%';")
    log("同步完成: %d 渠道(可用), %d 禁用, %s 模型(含 %s 统一模型)" % (active, dead, model_count, unified_count))
    log("=" * 55)


if __name__ == "__main__":
    main()
