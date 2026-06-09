#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自动从 GitHub 免费 API Key 仓库抓取 Key 并导入 New API
唯一来源: https://github.com/alistaitsacle/free-llm-api-keys
每30分钟由 crontab 执行

统一模型名称:
  - enlyai-chat: 自动路由到额度最高的聊天模型
  - enlyai-embedding: 自动路由到嵌入模型

功能:
  1. 并行测试渠道可用性（加速同步）
  2. 渠道健康监控（统计成功率）
  3. 智能路由优化（频繁失败的渠道临时降级）
  4. 全渠道不可用告警
"""

import re
import os
import json
import time
import subprocess
import urllib.request
import urllib.error
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

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
HEALTH_FILE = "/var/log/channel-health.json"
ALERT_LOG = "/var/log/channel-alerts.log"
TEST_WORKERS = 8  # 并行测试线程数
TEST_TIMEOUT = 15  # 单个渠道测试超时(秒)

# 永久免费提供商渠道（需要注册获取免费Key，但Key永久有效）
# 这些是稳定后备渠道，当共享Key全部不可用时保证服务可用性
# 在 ECS 上配置 /root/permanent-free-keys.json 文件来管理这些Key
PERMANENT_FREE_CONFIG = "/root/permanent-free-keys.json"
# 配置文件格式示例:
# [
#   {"name": "google-gemini", "base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
#    "key": "AIza...", "models": ["gemini-2.0-flash"], "priority": 7},
#   {"name": "groq-llama", "base_url": "https://api.groq.com/openai/v1",
#    "key": "gsk_...", "models": ["llama-3.3-70b-versatile"], "priority": 5},
#   {"name": "openrouter-free", "base_url": "https://openrouter.ai/api/v1",
#    "key": "sk-or-...", "models": ["google/gemini-2.0-flash-exp:free"], "priority": 3},
#   {"name": "github-models", "base_url": "https://models.inference.ai.azure.com",
#    "key": "ghp_...", "models": ["gpt-4o-mini", "Meta-Llama-3.3-70B-Instruct"], "priority": 5}
# ]

# 额外共享 Key 源（GitHub 仓库，格式与主源相同）
EXTRA_KEY_SOURCES = [
    # 如果有其他类似的共享 Key 仓库，可以在这里添加
    # {"repo": "user/repo", "file": "README.md", "branch": "main"},
]

# 模型能力分级（priority 越高越优先选择）
# 注意：永久免费提供商（ChatAnywhere/Agnes/OpenRouter）优先级高于共享Key
MODEL_TIERS = [
    # Tier 1: 永久免费顶级模型（稳定可靠，优先使用）
    ("gpt-5.4-mini-ca", 10), ("agnes-2.0-flash", 10),
    # Tier 2: 永久免费高级模型
    ("deepseek-v4-pro", 10),  # ChatAnywhere
    # Tier 3: 共享Key顶级模型（额度不稳定）
    ("gpt-5.5-pro", 3), ("openai/gpt-5.5-pro", 3),
    ("gpt-5.5", 3), ("openai/gpt-5.5", 3),
    ("claude-opus-4-7", 3), ("x-ai/grok-4.3", 3),
    # Tier 4: 共享Key高级模型
    ("gemini-2.5-flash", 3), ("deepseek/deepseek-v4-pro", 3),
    ("qwen/qwen3.6-max-preview", 3), ("qwen3.6-max-preview", 3),
    ("kimi-k2.5", 3), ("mistralai/mistral-medium-3-5", 3),
    ("openai/gpt-chat-latest", 3), ("gpt-chat-latest", 3),
    # Tier 5: 共享Key中级模型
    ("deepseek/deepseek-v4-flash", 3), ("deepseek-v4-flash", 3),
    ("smart-chat", 3),
    ("qwen/qwen3.6-35b-a3b", 3), ("qwen/qwen3.6-27b", 3),
    ("qwen/qwen3.6-flash", 3), ("qwen3.6-flash", 3),
    ("qwen/qwen3.5-plus-20260420", 3),
    ("google/gemini-3.1-flash-lite", 3), ("gemini-3.1-flash-lite", 3),
    ("inclusionai/ring-2.6-1t", 3), ("perceptron/perceptron-mk1", 3),
    # Tier 6: OpenRouter 免费模型
    ("moonshotai/kimi-k2.6:free", 5), ("openai/gpt-oss-120b:free", 5),
    ("qwen/qwen3-coder:free", 5), ("nvidia/nemotron-3-ultra-550b-a55b:free", 5),
    ("google/gemma-4-31b-it:free", 3), ("nvidia/nemotron-3-super-120b-a12b:free", 3),
    # Tier 7: 共享Key低级模型
    ("ibm-granite/granite-4.1-8b", 1), ("openrouter/owl-alpha", 1),
    ("poolside/laguna-xs.2:free", 1), ("poolside/laguna-m.1:free", 1),
    ("inclusionai/ling-2.6-1t:free", 1),
    ("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", 1),
    ("baidu/cobuddy:free", 1),
    # 其他永久免费提供商模型
    ("gemini-2.0-flash", 3), ("gemini-2.0-flash-exp:free", 3),
    ("google/gemini-2.0-flash-exp:free", 3),
    ("llama-3.3-70b-versatile", 3), ("llama-3.1-8b-instant", 1),
    ("llama-3.3-70b-instruct:free", 1), ("meta-llama/llama-3.3-70b-instruct:free", 1),
]

# 统一模型名称映射
UNIFIED_MODELS = {
    "enlyai-chat": [
        "gpt-5.5", "gpt-5.5-pro", "gpt-chat-latest",
        "claude-opus-4-7", "gemini-2.5-flash", "gemini-3.1-flash-lite",
        "gemini-2.0-flash", "gemini-2.0-flash-exp:free",
        "deepseek-v4-pro", "deepseek-v4-flash",
        "qwen/qwen3.6-max-preview", "qwen/qwen3.6-flash",
        "qwen/qwen3.6-27b", "qwen/qwen3.6-35b-a3b",
        "kimi-k2.5", "mistralai/mistral-medium-3-5",
        "x-ai/grok-4.3", "openai/gpt-5.5", "openai/gpt-5.5-pro",
        "openai/gpt-chat-latest", "deepseek/deepseek-v4-pro",
        "deepseek/deepseek-v4-flash", "google/gemini-3.1-flash-lite",
        "google/gemini-2.0-flash-exp:free",
        "inclusionai/ring-2.6-1t", "perceptron/perceptron-mk1",
        "ibm-granite/granite-4.1-8b", "qwen/qwen3.5-plus-20260420",
        "openrouter/owl-alpha", "smart-chat",
        "llama-3.3-70b-versatile", "llama-3.1-8b-instant",
        "llama-3.3-70b-instruct:free", "meta-llama/llama-3.3-70b-instruct:free",
        # ChatAnywhere 模型
        "gpt-5.4-mini-ca",
        # Agnes AI 模型
        "agnes-2.0-flash",
        # OpenRouter 免费模型
        "moonshotai/kimi-k2.6:free", "openai/gpt-oss-120b:free",
        "qwen/qwen3-coder:free", "google/gemma-4-31b-it:free",
        "nvidia/nemotron-3-ultra-550b-a55b:free",
        "nvidia/nemotron-3-super-120b-a12b:free",
        "poolside/laguna-xs.2:free", "poolside/laguna-m.1:free",
        "inclusionai/ling-2.6-1t:free",
        "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
        "baidu/cobuddy:free",
    ],
    "enlyai-embedding": ["text-embedding-3-small"]
}

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


def alert(msg):
    """写入告警日志"""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = "[%s] ALERT: %s" % (ts, msg)
    print(line)
    try:
        with open(ALERT_LOG, "a") as f:
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


def load_health_data():
    """加载渠道健康数据"""
    try:
        with open(HEALTH_FILE, "r") as f:
            return json.load(f)
    except:
        return {"channels": {}, "last_sync": None, "sync_history": []}


def save_health_data(data):
    """保存渠道健康数据"""
    try:
        with open(HEALTH_FILE, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    except:
        pass


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
    for exc in CHAT_MODEL_EXCLUDE:
        if exc in model.lower():
            return False
    return True


def get_unified_models_for(actual_model):
    result = []
    for unified, patterns in UNIFIED_MODELS.items():
        for pattern in patterns:
            if actual_model == pattern or actual_model.endswith(pattern):
                result.append(unified)
                break
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
    for pattern, priority in MODEL_TIERS:
        if model == pattern or model.endswith(pattern):
            return priority
    if ":free" in model:
        return 1
    if "embedding" in model:
        return 5
    return 5


def add_channel_with_abilities(key, model, channel_id):
    ts = int(time.time())
    channel_name = "free-key-sync-%d-%d" % (ts, channel_id)

    unified = get_unified_models_for(model)
    # 只将 enlyai-* 统一模型名放入 models 字段（不暴露上游实际模型名）
    models_list = list(set(unified))
    models_str = ",".join(models_list)

    mapping = {}
    for u in unified:
        mapping[u] = model
    mapping_str = json.dumps(mapping) if mapping else ""
    mapping_sql = mapping_str.replace("'", "''")

    priority = get_model_priority(model)
    weight = priority

    ok = psql_exec_silent(
        'INSERT INTO channels (id, name, type, key, base_url, models, model_mapping, "group", status, priority, weight, auto_ban, test_time, created_time) '
        "VALUES (%d, '%s', 1, '%s', '%s', '%s', '%s', 'default', 1, %d, %d, 0, 0, %d);" % (
            channel_id, channel_name, key, BACKEND_BASE_URL, models_str, mapping_sql, priority, weight, ts
        )
    )

    if ok:
        # 只将 enlyai-* 统一模型添加到 abilities（不暴露上游实际模型名）
        for m in models_list:
            if m.startswith("enlyai-"):
                psql_exec_silent(
                    'INSERT INTO abilities ("group", model, channel_id, enabled, priority, weight) '
                    "VALUES ('default', '%s', %d, true, %d, %d);" % (m, channel_id, priority, weight)
                )
        log("  渠道 #%d: %s (P%d) -> %s" % (channel_id, model, priority, "+".join(unified) if unified else "no-unified"))
        return True
    else:
        log("  渠道失败: %s" % channel_name)
        return False


def test_channel_upstream(key, model, base_url=None, timeout=TEST_TIMEOUT):
    """测试单个上游渠道是否可用，返回 (ok, error_msg)"""
    if base_url is None:
        base_url = BACKEND_BASE_URL
    # 规范化 base_url：去掉尾部斜杠和 /v1 后缀（后面会统一添加）
    base_url = base_url.rstrip("/")
    if base_url.endswith("/v1"):
        base_url = base_url[:-3]
    is_embedding = "embedding" in model.lower()

    if is_embedding:
        url = "%s/v1/embeddings" % base_url
        payload = json.dumps({"model": model, "input": "test"})
    else:
        url = "%s/v1/chat/completions" % base_url
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

    err_raw = data.get("error", "no_content")
    if isinstance(err_raw, dict):
        err_msg = err_raw.get("message", "no_content")[:100]
    elif isinstance(err_raw, str):
        err_msg = err_raw[:100]
    else:
        err_msg = "no_content"
    return (False, err_msg)


def test_single_channel(channel_info):
    """测试单个渠道（用于并行执行），返回 (ch_id, model, ok, error_msg)"""
    ch_id, ch_key, ch_models, ch_base_url, ch_mapping = channel_info
    # 从 model_mapping 获取实际上游模型名用于测试
    actual_model = None
    try:
        mapping = json.loads(ch_mapping) if ch_mapping else {}
        # 取第一个映射值作为测试模型
        if mapping:
            actual_model = list(mapping.values())[0]
    except:
        pass
    # 回退：如果 mapping 为空，用 models 字段第一个
    if not actual_model:
        actual_model = ch_models.split(",")[0].strip()
    ok, err = test_channel_upstream(ch_key, actual_model, base_url=ch_base_url)
    return (ch_id, actual_model, ok, err)


def test_and_disable_dead_channels():
    """并行测试所有渠道，禁用不可用的渠道。返回 (active_count, disabled_count, health_stats)"""
    log("开始并行测试渠道可用性 (workers=%d)..." % TEST_WORKERS)

    channels_str = psql_exec("SELECT id, key, models, base_url, model_mapping FROM channels WHERE status=1 ORDER BY id;")
    if not channels_str:
        log("没有活跃渠道需要测试")
        return (0, 0, {})

    # 解析渠道信息
    channel_list = []
    for line in channels_str.split("\n"):
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 5:
            continue
        ch_id = parts[0].strip()
        ch_key = parts[1].strip()
        ch_models = parts[2].strip()
        ch_base_url = parts[3].strip()
        ch_mapping = parts[4].strip()
        channel_list.append((ch_id, ch_key, ch_models, ch_base_url, ch_mapping))

    # 并行测试
    results = []
    with ThreadPoolExecutor(max_workers=TEST_WORKERS) as executor:
        futures = {executor.submit(test_single_channel, ch): ch for ch in channel_list}
        for future in as_completed(futures):
            try:
                result = future.result()
                results.append(result)
            except Exception as e:
                ch = futures[future]
                results.append((ch[0], ch[2].split(",")[0], False, str(e)[:60]))

    # 处理结果
    active = 0
    disabled = 0
    health_stats = {"chat_ok": 0, "chat_fail": 0, "embed_ok": 0, "embed_fail": 0,
                    "by_model": {}, "by_error": {}}

    for ch_id, model, ok, err in results:
        is_embedding = "embedding" in model.lower()

        if ok:
            active += 1
            if is_embedding:
                health_stats["embed_ok"] += 1
            else:
                health_stats["chat_ok"] += 1
            health_stats["by_model"].setdefault(model, {"ok": 0, "fail": 0})["ok"] += 1
            log("  渠道 #%s %s: 可用" % (ch_id, model))
        else:
            disabled += 1
            if is_embedding:
                health_stats["embed_fail"] += 1
            else:
                health_stats["chat_fail"] += 1
            health_stats["by_model"].setdefault(model, {"ok": 0, "fail": 0})["fail"] += 1
            # 分类错误
            err_type = "other"
            if "credits" in err.lower() or "insufficient" in err.lower():
                err_type = "no_credits"
            elif "rate limit" in err.lower():
                err_type = "rate_limit"
            elif "not found" in err.lower() or "no available channel" in err.lower():
                err_type = "model_not_found"
            elif "suspended" in err.lower() or "not active" in err.lower():
                err_type = "account_suspended"
            elif "invalid" in err.lower():
                err_type = "invalid_token"
            health_stats["by_error"].setdefault(err_type, 0)
            health_stats["by_error"][err_type] += 1
            log("  渠道 #%s %s: 不可用 [%s] (%s) -> 禁用" % (ch_id, model, err_type, err[:50]))
            psql_exec("UPDATE channels SET status=2 WHERE id=%s;" % ch_id)
            psql_exec("DELETE FROM abilities WHERE channel_id=%s;" % ch_id)

    log("渠道测试完成: %d 可用, %d 禁用" % (active, disabled))
    return (active, disabled, health_stats)


def apply_smart_routing(health_data):
    """智能路由优化：根据历史健康数据调整渠道优先级
    - 连续3次失败的模型类型，降低其优先级
    - 连续5次失败的模型类型，完全禁用
    """
    log("应用智能路由优化...")

    channels_str = psql_exec(
        "SELECT id, models, priority, model_mapping FROM channels WHERE status=1 ORDER BY id;"
    )
    if not channels_str:
        return

    for line in channels_str.split("\n"):
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue

        ch_id = parts[0].strip()
        ch_models = parts[1].strip()
        ch_priority = int(parts[2].strip())
        ch_mapping = parts[3].strip()

        # 从 model_mapping 获取实际上游模型名
        actual_model = None
        try:
            mapping = json.loads(ch_mapping) if ch_mapping else {}
            if mapping:
                actual_model = list(mapping.values())[0]
        except:
            pass
        if not actual_model:
            actual_model = ch_models.split(",")[0].strip()

        # 检查历史健康数据
        model_health = health_data.get("channels", {}).get(actual_model, {})
        consecutive_fails = model_health.get("consecutive_fails", 0)

        if consecutive_fails >= 5:
            # 连续5次失败，禁用渠道
            log("  智能路由: #%s %s 连续%d次失败 -> 禁用" % (ch_id, actual_model, consecutive_fails))
            psql_exec("UPDATE channels SET status=2 WHERE id=%s;" % ch_id)
            psql_exec("DELETE FROM abilities WHERE channel_id=%s;" % ch_id)
        elif consecutive_fails >= 3:
            # 连续3次失败，降低优先级
            new_priority = max(1, ch_priority - 3)
            new_weight = new_priority
            if new_priority < ch_priority:
                log("  智能路由: #%s %s 连续%d次失败 -> 优先级 P%d->P%d" % (
                    ch_id, actual_model, consecutive_fails, ch_priority, new_priority))
                psql_exec(
                    'UPDATE channels SET priority=%d, weight=%d WHERE id=%s;' % (
                        new_priority, new_weight, ch_id))
                psql_exec(
                    'UPDATE abilities SET priority=%d, weight=%d WHERE channel_id=%s;' % (
                        new_priority, new_weight, ch_id))


def check_and_alert(active, health_stats):
    """检查是否需要告警"""
    chat_ok = health_stats.get("chat_ok", 0)
    embed_ok = health_stats.get("embed_ok", 0)

    if chat_ok == 0:
        alert("所有聊天渠道不可用！enlyai-chat 将无法使用")
    if embed_ok == 0:
        alert("所有嵌入渠道不可用！enlyai-embedding 将无法使用")
    if active == 0:
        alert("所有渠道不可用！系统完全无法服务")

    # 告警错误分布
    by_error = health_stats.get("by_error", {})
    if by_error.get("no_credits", 0) > 5:
        alert("大量渠道额度不足 (%d个)，免费Key可能已耗尽" % by_error["no_credits"])


def update_health_data(health_data, active, disabled, health_stats, total_keys):
    """更新健康数据文件"""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # 更新各模型的历史数据
    by_model = health_stats.get("by_model", {})
    channels = health_data.get("channels", {})

    for model, stats in by_model.items():
        if model not in channels:
            channels[model] = {"total_tests": 0, "total_ok": 0, "consecutive_fails": 0}

        channels[model]["total_tests"] += stats["ok"] + stats["fail"]
        channels[model]["total_ok"] += stats["ok"]

        if stats["ok"] > 0:
            channels[model]["consecutive_fails"] = 0
        else:
            channels[model]["consecutive_fails"] += 1

        channels[model]["last_test"] = now
        channels[model]["success_rate"] = "%.1f%%" % (
            100.0 * channels[model]["total_ok"] / max(1, channels[model]["total_tests"])
        )

    # 更新同步历史
    sync_record = {
        "time": now,
        "total_keys": total_keys,
        "active": active,
        "disabled": disabled,
        "chat_ok": health_stats.get("chat_ok", 0),
        "embed_ok": health_stats.get("embed_ok", 0),
        "errors": health_stats.get("by_error", {})
    }

    history = health_data.get("sync_history", [])
    history.append(sync_record)
    # 只保留最近 48 条记录（24小时，每30分钟一条）
    if len(history) > 48:
        history = history[-48:]

    health_data["channels"] = channels
    health_data["last_sync"] = now
    health_data["sync_history"] = history
    save_health_data(health_data)


def ensure_model_pricing():
    """确保所有模型都有价格配置（New API 要求模型必须有价格才能使用）"""
    log("更新模型价格配置...")

    # 获取所有当前活跃的模型
    models_str = psql_exec(
        "SELECT DISTINCT model FROM abilities WHERE enabled=true;"
    )
    if not models_str:
        return

    models = [m.strip() for m in models_str.split("\n") if m.strip()]

    # 获取当前 ModelRatio 和 CompletionRatio
    mr_str = psql_exec("SELECT value FROM options WHERE key='ModelRatio';")
    cr_str = psql_exec("SELECT value FROM options WHERE key='CompletionRatio';")

    try:
        model_ratio = json.loads(mr_str) if mr_str else {}
    except:
        model_ratio = {}
    try:
        completion_ratio = json.loads(cr_str) if cr_str else {}
    except:
        completion_ratio = {}

    updated = False
    for model in models:
        if model not in model_ratio:
            model_ratio[model] = 0.0001
            updated = True
        if model not in completion_ratio:
            completion_ratio[model] = 0.0001
            updated = True

    if updated:
        mr_sql = json.dumps(model_ratio).replace("'", "''")
        cr_sql = json.dumps(completion_ratio).replace("'", "''")
        psql_exec_silent(
            "UPDATE options SET value='%s' WHERE key='ModelRatio';" % mr_sql)
        psql_exec_silent(
            "UPDATE options SET value='%s' WHERE key='CompletionRatio';" % cr_sql)
        log("  更新了 %d 个模型的价格配置" % len(models))
    else:
        log("  所有模型价格已配置")


def add_permanent_free_channels(start_id):
    """加载并添加永久免费提供商渠道（从配置文件）"""
    log("加载永久免费提供商渠道...")
    try:
        with open(PERMANENT_FREE_CONFIG, "r") as f:
            channels = json.load(f)
    except:
        log("  未找到配置文件 %s，跳过永久免费渠道" % PERMANENT_FREE_CONFIG)
        return 0

    if not channels:
        log("  配置文件为空，跳过永久免费渠道")
        return 0

    added = 0
    ch_id = start_id
    for ch in channels:
        name = ch.get("name", "permanent-free-%d" % ch_id)
        base_url = ch.get("base_url", "")
        key = ch.get("key", "")
        models = ch.get("models", [])
        priority = ch.get("priority", 5)

        if not base_url or not key or not models:
            log("  跳过无效配置: %s" % name)
            continue

        ts = int(time.time())
        channel_name = "permanent-%s" % name

        # 为每个模型创建统一模型映射
        # 只将 enlyai-* 统一模型名放入 models 字段（不暴露上游实际模型名）
        unified_models = []
        for model in models:
            unified = get_unified_models_for(model)
            for u in unified:
                if u not in unified_models:
                    unified_models.append(u)

        models_str = ",".join(unified_models)
        mapping = {}
        for model in models:
            for u in get_unified_models_for(model):
                mapping[u] = model
        mapping_str = json.dumps(mapping) if mapping else ""
        mapping_sql = mapping_str.replace("'", "''")

        # 规范化 base_url：New API 会自动添加 /v1，所以去掉 /v1 后缀
        clean_base_url = base_url.rstrip("/")
        if clean_base_url.endswith("/v1"):
            clean_base_url = clean_base_url[:-3]

        weight = priority
        ok = psql_exec_silent(
            'INSERT INTO channels (id, name, type, key, base_url, models, model_mapping, "group", status, priority, weight, auto_ban, test_time, created_time) '
            "VALUES (%d, '%s', 1, '%s', '%s', '%s', '%s', 'default', 1, %d, %d, 0, 0, %d);" % (
                ch_id, channel_name, key, clean_base_url, models_str, mapping_sql, priority, weight, ts
            )
        )

        if ok:
            # 只将 enlyai-* 统一模型添加到 abilities（不暴露上游实际模型名）
            for m in unified_models:
                if m.startswith("enlyai-"):
                    psql_exec_silent(
                        'INSERT INTO abilities ("group", model, channel_id, enabled, priority, weight) '
                        "VALUES ('default', '%s', %d, true, %d, %d);" % (m, ch_id, priority, weight)
                    )
            log("  永久渠道 #%d: %s (P%d) -> %s" % (ch_id, name, priority, ",".join(models)))
            added += 1
        else:
            log("  永久渠道失败: %s" % name)

        ch_id += 1

    log("  添加了 %d 个永久免费渠道" % added)
    return added


# ====== Token 权限管理 ======

# 新注册用户的 Token 限制策略
TOKEN_EXPIRE_DAYS = 30          # Token 有效期（天）
TOKEN_MAX_QUOTA = 500000        # 最大额度（约500次对话）
ADMIN_USER_IDS = [1]            # 管理员用户 ID 列表（不受限制）


def enforce_token_limits():
    """强制执行非管理员用户的 Token 限制：有限额度 + 有效期"""
    log("检查用户 Token 权限...")

    # 获取所有非管理员的活跃 Token
    tokens_str = psql_exec(
        "SELECT id, user_id, name, expired_time, remain_quota, unlimited_quota "
        "FROM tokens WHERE deleted_at IS NULL AND user_id NOT IN (%s);"
        % ",".join(str(uid) for uid in ADMIN_USER_IDS)
    )
    if not tokens_str:
        log("  没有需要检查的非管理员 Token")
        return

    now = int(time.time())
    expire_at = now + TOKEN_EXPIRE_DAYS * 86400
    fixed = 0

    for line in tokens_str.split("\n"):
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 6:
            continue
        tid = parts[0].strip()
        expired_time = parts[3].strip()
        remain_quota = parts[4].strip()
        unlimited = parts[5].strip()

        needs_fix = False
        updates = []

        # 修复无限额度
        if unlimited.lower() == "t" or unlimited == "true":
            updates.append("unlimited_quota=false")
            needs_fix = True

        # 修复永不过期（expired_time = -1）
        if expired_time == "-1":
            updates.append("expired_time=%d" % expire_at)
            needs_fix = True

        # 修复额度过高
        try:
            if int(remain_quota) > TOKEN_MAX_QUOTA and unlimited.lower() != "t":
                updates.append("remain_quota=%d" % TOKEN_MAX_QUOTA)
                needs_fix = True
        except ValueError:
            pass

        if needs_fix:
            sql = "UPDATE tokens SET %s WHERE id=%s;" % (", ".join(updates), tid)
            psql_exec(sql)
            fixed += 1
            log("  Token #%s: %s" % (tid, ", ".join(updates)))

    # 同时设置 QuotaForNewUser
    psql_exec("UPDATE options SET value='%d' WHERE key='QuotaForNewUser';" % TOKEN_MAX_QUOTA)

    if fixed > 0:
        log("  修复了 %d 个 Token（额度上限=%d, 有效期=%d天）" % (fixed, TOKEN_MAX_QUOTA, TOKEN_EXPIRE_DAYS))
    else:
        log("  所有非管理员 Token 权限正常")


def main():
    start_time = time.time()
    log("=" * 55)
    log("同步免费 API Key (唯一来源: alistaitsacle/free-llm-api-keys)")
    log("统一模型: enlyai-chat (聊天), enlyai-embedding (嵌入)")
    log("=" * 55)

    # 加载健康数据
    health_data = load_health_data()
    # 清理旧健康数据中的 consecutive_fails（渠道已重建，旧数据不适用）
    for model_name in list(health_data.get("channels", {}).keys()):
        health_data["channels"][model_name]["consecutive_fails"] = 0

    # 1. Fetch key-model pairs
    all_pairs = []
    for source in KEY_SOURCES + EXTRA_KEY_SOURCES:
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

    # 5.5 Add permanent free channels (stable fallback)
    permanent_added = add_permanent_free_channels(next_id)
    next_id += permanent_added

    # 5.6 Ensure all models have pricing (required by New API)
    ensure_model_pricing()

    # 5.7 Clean up models table: only keep enlyai-* models (hide upstream model names)
    psql_exec("DELETE FROM models WHERE model_name NOT LIKE 'enlyai-%';")
    log("清理 models 表：只保留 enlyai-* 模型")

    # 6. Apply smart routing (based on historical health data)
    apply_smart_routing(health_data)

    # 7. Parallel test channels and disable dead ones
    active, dead, health_stats = test_and_disable_dead_channels()

    # 8. Check and alert
    check_and_alert(active, health_stats)

    # 9. Update health data
    update_health_data(health_data, active, dead, health_stats, len(unique_pairs))

    # 10. Enforce token limits for non-admin users
    enforce_token_limits()

    # 11. Verify
    ch_count = psql_exec("SELECT COUNT(*) FROM channels WHERE status=1;")
    model_count = psql_exec("SELECT COUNT(DISTINCT model) FROM abilities WHERE enabled=true;")
    unified_count = psql_exec(
        "SELECT COUNT(DISTINCT model) FROM abilities WHERE enabled=true AND model LIKE 'enlyai-%';")

    elapsed = int(time.time() - start_time)
    log("同步完成: %d 可用, %d 禁用, %s 模型(含 %s 统一模型), 耗时 %ds" % (
        active, dead, model_count, unified_count, elapsed))
    log("健康统计: chat=%d可用/%d失败, embed=%d可用/%d失败, 错误分布=%s" % (
        health_stats.get("chat_ok", 0), health_stats.get("chat_fail", 0),
        health_stats.get("embed_ok", 0), health_stats.get("embed_fail", 0),
        json.dumps(health_stats.get("by_error", {}))))
    log("=" * 55)


if __name__ == "__main__":
    main()
