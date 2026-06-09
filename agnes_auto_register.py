#!/usr/bin/env python3
"""
Agnes AI 自动注册脚本
- 使用临时邮箱获取验证邮件
- Playwright 自动化注册流程
- 提取 API Key
- 发送结果到指定邮箱
- 生成账号信息表格

使用前请安装依赖：
  pip install playwright requests
  playwright install chromium

配置说明：
  修改下方 CONFIG 部分的参数后运行
"""

import json
import time
import random
import string
import smtplib
import csv
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
from pathlib import Path

import requests
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout

# ============================================================
# CONFIG - 请根据实际情况修改
# ============================================================
CONFIG = {
    # 目标平台
    "platform_url": "https://platform.agnes-ai.com/login",
    "platform_name": "Agnes AI",

    # 临时邮箱 API (使用 mail.tm 或类似服务)
    # mail.tm 是免费临时邮箱服务，无需 API Key
    "temp_mail_api": "https://api.mail.tm",

    # 结果发送邮箱 (SMTP 配置)
    "smtp_host": "smtp.126.com",
    "smtp_port": 465,  # SSL 端口
    "smtp_user": "",    # 你的 126 邮箱账号
    "smtp_pass": "",    # 你的 126 邮箱授权码（非登录密码）
    "target_email": "xlf_iou@126.com",

    # 注册数量
    "register_count": 1,

    # 输出文件
    "output_csv": "agnes_accounts.csv",
    "output_json": "agnes_accounts.json",

    # 浏览器配置
    "headless": True,
    "slow_mo": 500,  # 操作间隔(ms)，模拟人类速度
}

# ============================================================
# 临时邮箱模块
# ============================================================
class TempMail:
    """使用 mail.tm API 获取临时邮箱"""

    def __init__(self, api_base=None):
        self.api_base = api_base or CONFIG["temp_mail_api"]
        self.token = None
        self.account_id = None
        self.email = None
        self.password = None

    def _get_available_domains(self):
        """获取可用的邮箱域名"""
        resp = requests.get(f"{self.api_base}/domains", timeout=10)
        resp.raise_for_status()
        domains = resp.json().get("hydra:member", [])
        if not domains:
            raise Exception("没有可用的临时邮箱域名")
        return domains

    def create_account(self):
        """创建临时邮箱账户"""
        domains = self._get_available_domains()
        domain = domains[0]["domain"]

        # 生成随机用户名
        username = "".join(random.choices(string.ascii_lowercase + string.digits, k=10))
        self.email = f"{username}@{domain}"
        self.password = "".join(random.choices(string.ascii_letters + string.digits, k=12))

        # 注册
        resp = requests.post(
            f"{self.api_base}/accounts",
            json={"address": self.email, "password": self.password},
            timeout=10,
        )

        if resp.status_code not in (200, 201):
            # mail.tm 可能需要不同的注册方式
            raise Exception(f"创建临时邮箱失败: {resp.status_code} {resp.text}")

        data = resp.json()
        self.account_id = data.get("id")

        # 登录获取 token
        resp = requests.post(
            f"{self.api_base}/token",
            json={"address": self.email, "password": self.password},
            timeout=10,
        )
        if resp.status_code != 200:
            raise Exception(f"临时邮箱登录失败: {resp.status_code} {resp.text}")

        self.token = resp.json().get("token")
        return self.email

    def get_messages(self, wait_seconds=60, poll_interval=5):
        """等待并获取邮件"""
        headers = {"Authorization": f"Bearer {self.token}"}
        start = time.time()

        while time.time() - start < wait_seconds:
            resp = requests.get(
                f"{self.api_base}/messages",
                headers=headers,
                timeout=10,
            )
            if resp.status_code == 200:
                messages = resp.json().get("hydra:member", [])
                if messages:
                    return messages
            time.sleep(poll_interval)

        raise Exception(f"等待邮件超时 ({wait_seconds}s)")

    def get_message_content(self, message_id):
        """获取邮件详情"""
        headers = {"Authorization": f"Bearer {self.token}"}
        resp = requests.get(
            f"{self.api_base}/messages/{message_id}",
            headers=headers,
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json()


# ============================================================
# 邮件发送模块
# ============================================================
class EmailSender:
    """通过 SMTP 发送结果邮件"""

    def __init__(self, config=None):
        cfg = config or CONFIG
        self.host = cfg["smtp_host"]
        self.port = cfg["smtp_port"]
        self.user = cfg["smtp_user"]
        self.pass_ = cfg["smtp_pass"]

    def send(self, to_email, subject, html_body):
        """发送 HTML 邮件"""
        if not self.user or not self.pass_:
            print("[WARN] SMTP 未配置，跳过邮件发送")
            print(f"[INFO] 邮件内容预览:\n{html_body[:500]}...")
            return False

        msg = MIMEMultipart("alternative")
        msg["From"] = self.user
        msg["To"] = to_email
        msg["Subject"] = subject

        msg.attach(MIMEText(html_body, "html", "utf-8"))

        try:
            with smtplib.SMTP_SSL(self.host, self.port) as server:
                server.login(self.user, self.pass_)
                server.sendmail(self.user, [to_email], msg.as_string())
            print(f"[OK] 邮件已发送至 {to_email}")
            return True
        except Exception as e:
            print(f"[ERROR] 邮件发送失败: {e}")
            return False


# ============================================================
# Playwright 自动化注册模块
# ============================================================
class AgnesRegistrar:
    """Agnes AI 平台自动注册"""

    def __init__(self, config=None):
        self.cfg = config or CONFIG
        self.accounts = []

    def _generate_password(self, length=14):
        chars = string.ascii_letters + string.digits + "!@#$%"
        return "".join(random.choices(chars, k=length))

    def _generate_name(self):
        first_names = ["Alex", "Jordan", "Taylor", "Morgan", "Casey",
                       "Riley", "Quinn", "Avery", "Blake", "Cameron"]
        last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones",
                      "Garcia", "Miller", "Davis", "Rodriguez", "Martinez"]
        return random.choice(first_names), random.choice(last_names)

    def register_account(self, email, password=None):
        """注册一个 Agnes AI 账号，返回账号信息字典"""
        if not password:
            password = self._generate_password()

        first_name, last_name = self._generate_name()
        api_key = None

        print(f"\n{'='*50}")
        print(f"[INFO] 开始注册: {email}")
        print(f"{'='*50}")

        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=self.cfg["headless"],
                slow_mo=self.cfg["slow_mo"],
            )
            context = browser.new_context(
                viewport={"width": 1280, "height": 800},
                user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                           "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            )
            page = context.new_page()

            try:
                # 1. 打开登录/注册页面
                print("[STEP 1] 打开 Agnes AI 登录页面...")
                page.goto(self.cfg["platform_url"], wait_until="networkidle", timeout=30000)
                time.sleep(2)

                # 2. 查找注册入口
                # 常见模式：页面上有 "Sign Up" / "Register" / "Create Account" 按钮
                # 或者登录表单上有切换到注册的链接
                print("[STEP 2] 查找注册入口...")

                # 尝试多种选择器
                signup_selectors = [
                    'text="Sign Up"',
                    'text="Register"',
                    'text="Create Account"',
                    'text="注册"',
                    'text="Sign up"',
                    'a[href*="register"]',
                    'a[href*="signup"]',
                    'button:has-text("Sign")',
                ]

                signup_clicked = False
                for selector in signup_selectors:
                    try:
                        elem = page.locator(selector).first
                        if elem.is_visible(timeout=2000):
                            elem.click()
                            signup_clicked = True
                            print(f"[OK] 点击了注册按钮: {selector}")
                            time.sleep(2)
                            break
                    except Exception:
                        continue

                if not signup_clicked:
                    print("[WARN] 未找到注册按钮，尝试直接在当前页面填写...")

                # 3. 截图保存当前页面状态（调试用）
                screenshot_path = f"debug_step2_{int(time.time())}.png"
                page.screenshot(path=screenshot_path)
                print(f"[DEBUG] 页面截图已保存: {screenshot_path}")

                # 4. 填写注册表单
                print("[STEP 3] 填写注册表单...")

                # 常见注册表单字段
                form_filled = False

                # 尝试填写邮箱
                email_selectors = [
                    'input[type="email"]',
                    'input[name="email"]',
                    'input[placeholder*="email" i]',
                    'input[placeholder*="邮箱"]',
                    'input[id*="email" i]',
                ]
                for sel in email_selectors:
                    try:
                        elem = page.locator(sel).first
                        if elem.is_visible(timeout=2000):
                            elem.fill(email)
                            form_filled = True
                            print(f"[OK] 填写邮箱: {sel}")
                            break
                    except Exception:
                        continue

                # 尝试填写密码
                password_selectors = [
                    'input[type="password"]',
                    'input[name="password"]',
                    'input[placeholder*="password" i]',
                    'input[placeholder*="密码"]',
                ]
                pwd_filled = False
                for sel in password_selectors:
                    try:
                        elems = page.locator(sel)
                        count = elems.count()
                        for i in range(count):
                            elem = elems.nth(i)
                            if elem.is_visible(timeout=1000):
                                if not pwd_filled:
                                    elem.fill(password)
                                    pwd_filled = True
                                    print(f"[OK] 填写密码: {sel}[{i}]")
                                # 如果有确认密码字段
                                elif pwd_filled:
                                    elem.fill(password)
                                    print(f"[OK] 填写确认密码: {sel}[{i}]")
                                    break
                    except Exception:
                        continue

                # 尝试填写姓名
                name_selectors = [
                    'input[name="name"]',
                    'input[name="firstName"]',
                    'input[placeholder*="name" i]',
                    'input[placeholder*="姓名"]',
                ]
                for sel in name_selectors:
                    try:
                        elem = page.locator(sel).first
                        if elem.is_visible(timeout=1000):
                            elem.fill(f"{first_name} {last_name}")
                            print(f"[OK] 填写姓名: {sel}")
                            break
                    except Exception:
                        continue

                # 截图
                screenshot_path2 = f"debug_step3_{int(time.time())}.png"
                page.screenshot(path=screenshot_path2)
                print(f"[DEBUG] 表单截图已保存: {screenshot_path2}")

                # 5. 提交注册
                print("[STEP 4] 提交注册...")
                submit_selectors = [
                    'button[type="submit"]',
                    'button:has-text("Sign Up")',
                    'button:has-text("Register")',
                    'button:has-text("Create")',
                    'button:has-text("注册")',
                    'input[type="submit"]',
                ]

                for sel in submit_selectors:
                    try:
                        elem = page.locator(sel).first
                        if elem.is_visible(timeout=2000):
                            elem.click()
                            print(f"[OK] 点击提交按钮: {sel}")
                            break
                    except Exception:
                        continue

                time.sleep(5)

                # 截图注册后页面
                screenshot_path3 = f"debug_step4_{int(time.time())}.png"
                page.screenshot(path=screenshot_path3)
                print(f"[DEBUG] 注册后截图已保存: {screenshot_path3}")

                # 6. 检查是否需要邮箱验证
                print("[STEP 5] 检查邮箱验证...")
                page_content = page.content()
                if "verif" in page_content.lower() or "confirm" in page_content.lower():
                    print("[INFO] 平台要求邮箱验证，请手动完成验证后重新运行脚本获取 API Key")
                    print("[INFO] 或者配置临时邮箱自动获取验证链接")

                # 7. 尝试获取 API Key
                print("[STEP 6] 尝试获取 API Key...")

                # 尝试导航到 API Key 页面
                api_key_urls = [
                    f"{self.cfg['platform_url'].rsplit('/', 1)[0]}/api-keys",
                    f"{self.cfg['platform_url'].rsplit('/', 1)[0]}/settings/api-keys",
                    f"{self.cfg['platform_url'].rsplit('/', 1)[0]}/dashboard",
                ]

                for url in api_key_urls:
                    try:
                        page.goto(url, wait_until="networkidle", timeout=10000)
                        time.sleep(2)
                        # 查找 API Key 显示
                        key_selectors = [
                            'code',
                            'input[value*="sk-"]',
                            'input[value*="key"]',
                            '.api-key',
                            '[data-testid*="api-key"]',
                        ]
                        for sel in key_selectors:
                            try:
                                elem = page.locator(sel).first
                                if elem.is_visible(timeout=2000):
                                    text = elem.text_content or elem.input_value()
                                    if text and len(text) > 10:
                                        api_key = text.strip()
                                        print(f"[OK] 找到 API Key: {api_key[:8]}...")
                                        break
                            except Exception:
                                continue
                        if api_key:
                            break
                    except Exception:
                        continue

                if not api_key:
                    # 尝试创建 API Key
                    create_selectors = [
                        'button:has-text("Create")',
                        'button:has-text("Generate")',
                        'button:has-text("New")',
                        'button:has-text("创建")',
                    ]
                    for sel in create_selectors:
                        try:
                            elem = page.locator(sel).first
                            if elem.is_visible(timeout=2000):
                                elem.click()
                                time.sleep(3)
                                print(f"[OK] 点击创建 API Key: {sel}")
                                break
                        except Exception:
                            continue

                    # 再次查找
                    time.sleep(2)
                    for sel in ['code', 'input[value*="sk-"]', '.api-key']:
                        try:
                            elem = page.locator(sel).first
                            if elem.is_visible(timeout=2000):
                                text = elem.text_content or elem.input_value()
                                if text and len(text) > 10:
                                    api_key = text.strip()
                                    print(f"[OK] 获取到 API Key: {api_key[:8]}...")
                                    break
                        except Exception:
                            continue

                # 最终截图
                screenshot_path4 = f"debug_final_{int(time.time())}.png"
                page.screenshot(path=screenshot_path4)
                print(f"[DEBUG] 最终截图已保存: {screenshot_path4}")

            except PlaywrightTimeout as e:
                print(f"[ERROR] 页面超时: {e}")
            except Exception as e:
                print(f"[ERROR] 注册过程出错: {e}")
            finally:
                browser.close()

        account_info = {
            "platform": self.cfg["platform_name"],
            "email": email,
            "password": password,
            "name": f"{first_name} {last_name}",
            "api_key": api_key or "未获取（需手动操作）",
            "registered_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "成功" if api_key else "需手动完成",
        }

        self.accounts.append(account_info)
        print(f"\n[RESULT] 注册结果:")
        for k, v in account_info.items():
            print(f"  {k}: {v}")

        return account_info


# ============================================================
# 结果整理模块
# ============================================================
class ResultManager:
    """整理账号信息，生成表格和邮件"""

    def __init__(self, accounts, config=None):
        self.accounts = accounts
        self.cfg = config or CONFIG

    def save_csv(self):
        """保存为 CSV 文件"""
        if not self.accounts:
            print("[WARN] 没有账号数据可保存")
            return

        filepath = self.cfg["output_csv"]
        with open(filepath, "w", newline="", encoding="utf-8-sig") as f:
            writer = csv.DictWriter(f, fieldnames=self.accounts[0].keys())
            writer.writeheader()
            writer.writerows(self.accounts)

        print(f"[OK] CSV 已保存: {filepath}")

    def save_json(self):
        """保存为 JSON 文件"""
        if not self.accounts:
            return

        filepath = self.cfg["output_json"]
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(self.accounts, f, ensure_ascii=False, indent=2)

        print(f"[OK] JSON 已保存: {filepath}")

    def generate_email_html(self):
        """生成邮件 HTML 内容"""
        rows = ""
        for i, acc in enumerate(self.accounts, 1):
            rows += f"""
            <tr>
                <td>{i}</td>
                <td>{acc['platform']}</td>
                <td>{acc['email']}</td>
                <td>{acc['password']}</td>
                <td>{acc['name']}</td>
                <td><code>{acc['api_key']}</code></td>
                <td>{acc['registered_at']}</td>
                <td>{acc['status']}</td>
            </tr>"""

        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; padding: 20px; }}
                h2 {{ color: #333; }}
                table {{ border-collapse: collapse; width: 100%; margin-top: 15px; }}
                th, td {{ border: 1px solid #ddd; padding: 10px; text-align: left; font-size: 13px; }}
                th {{ background-color: #4CAF50; color: white; }}
                tr:nth-child(even) {{ background-color: #f2f2f2; }}
                code {{ background: #f4f4f4; padding: 2px 6px; border-radius: 3px; font-size: 12px; }}
                .footer {{ margin-top: 20px; color: #888; font-size: 12px; }}
            </style>
        </head>
        <body>
            <h2>Agnes AI 账号注册结果</h2>
            <p>共注册 <strong>{len(self.accounts)}</strong> 个账号，详情如下：</p>
            <table>
                <thead>
                    <tr>
                        <th>序号</th>
                        <th>平台</th>
                        <th>邮箱</th>
                        <th>密码</th>
                        <th>姓名</th>
                        <th>API Key</th>
                        <th>注册时间</th>
                        <th>状态</th>
                    </tr>
                </thead>
                <tbody>{rows}</tbody>
            </table>
            <div class="footer">
                <p>此邮件由自动注册脚本生成 | {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            </div>
        </body>
        </html>
        """
        return html


# ============================================================
# 主流程
# ============================================================
def main():
    print("=" * 60)
    print("  Agnes AI 自动注册脚本")
    print("=" * 60)

    # 检查 SMTP 配置
    if not CONFIG["smtp_user"] or not CONFIG["smtp_pass"]:
        print("\n[WARN] SMTP 未配置！邮件发送将跳过。")
        print("  请在脚本 CONFIG 部分填写:")
        print("  - smtp_user: 你的 126 邮箱账号")
        print("  - smtp_pass: 你的 126 邮箱授权码")
        print("  授权码获取: 126邮箱 -> 设置 -> POP3/SMTP/IMAP -> 开启并获取授权码")
        print()

    # 初始化模块
    registrar = AgnesRegistrar()
    sender = EmailSender()

    accounts = []

    for i in range(CONFIG["register_count"]):
        print(f"\n{'#'*60}")
        print(f"  注册第 {i+1}/{CONFIG['register_count']} 个账号")
        print(f"{'#'*60}")

        try:
            # 1. 创建临时邮箱
            print("[STEP 0] 创建临时邮箱...")
            mail = TempMail()
            email = mail.create_account()
            print(f"[OK] 临时邮箱: {email}")

            # 2. 注册账号
            account = registrar.register_account(email)
            accounts.append(account)

            # 3. 如果需要邮箱验证，尝试获取验证邮件
            if account["status"] == "需手动完成":
                print("[INFO] 尝试获取验证邮件...")
                try:
                    messages = mail.get_messages(wait_seconds=30)
                    if messages:
                        msg = messages[0]
                        content = mail.get_message_content(msg["id"])
                        print(f"[OK] 收到邮件: {content.get('subject', '无主题')}")
                        # TODO: 解析验证链接并自动点击
                        print("[INFO] 请手动点击验证链接完成注册")
                except Exception as e:
                    print(f"[WARN] 获取验证邮件失败: {e}")

        except Exception as e:
            print(f"[ERROR] 第 {i+1} 个账号注册失败: {e}")
            accounts.append({
                "platform": CONFIG["platform_name"],
                "email": "失败",
                "password": "-",
                "name": "-",
                "api_key": "-",
                "registered_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "status": f"失败: {e}",
            })

        # 间隔，避免频率过高
        if i < CONFIG["register_count"] - 1:
            delay = random.randint(10, 30)
            print(f"[INFO] 等待 {delay}s 后继续...")
            time.sleep(delay)

    # 4. 整理结果
    print(f"\n{'='*60}")
    print("  整理结果")
    print(f"{'='*60}")

    result_mgr = ResultManager(accounts)
    result_mgr.save_csv()
    result_mgr.save_json()

    # 5. 发送邮件
    print("\n[STEP] 发送结果邮件...")
    html = result_mgr.generate_email_html()
    sender.send(
        to_email=CONFIG["target_email"],
        subject=f"Agnes AI 账号注册结果 - {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        html_body=html,
    )

    # 6. 打印汇总
    print(f"\n{'='*60}")
    print("  注册汇总")
    print(f"{'='*60}")
    print(f"  总计: {len(accounts)} 个账号")
    success = sum(1 for a in accounts if a["status"] == "成功")
    print(f"  成功: {success} 个")
    print(f"  需手动完成: {len(accounts) - success} 个")
    print(f"  CSV: {CONFIG['output_csv']}")
    print(f"  JSON: {CONFIG['output_json']}")
    print()

    # 打印表格
    print(f"{'序号':<4} {'邮箱':<35} {'API Key':<25} {'状态'}")
    print("-" * 80)
    for i, acc in enumerate(accounts, 1):
        key_display = acc["api_key"][:20] + "..." if len(acc["api_key"]) > 20 else acc["api_key"]
        print(f"{i:<4} {acc['email']:<35} {key_display:<25} {acc['status']}")


if __name__ == "__main__":
    main()
