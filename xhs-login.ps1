$ErrorActionPreference = "Stop"

$Repo = "Robust1197/pathToFreedeom"
$PublicApp = "https://robust1197.github.io/mansion-tracker-app/"
$TempDir = Join-Path $env:TEMP "mansion-tracker-xhs-login"
$StatePath = Join-Path $TempDir "xhs-storage-state.json"
$PyPath = Join-Path $TempDir "xhs_login_helper.py"

Write-Host ""
Write-Host "=== 小红书重新登录助手 ===" -ForegroundColor Cyan
Write-Host "这个脚本只做三件事："
Write-Host "1. 打开真实小红书登录页"
Write-Host "2. 保存登录态到临时文件"
Write-Host "3. 直接写入 GitHub Actions Secret（不会把 Cookie 打印出来）"
Write-Host ""

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

function Find-Python {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        return @("py", "-3")
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return @("python")
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "没有检测到 Python，正在自动安装 Python 3.12..." -ForegroundColor Yellow
        winget install --id Python.Python.3.12 -e --source winget --accept-source-agreements --accept-package-agreements
        $possible = @(
            "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
            "$env:ProgramFiles\Python312\python.exe"
        )
        foreach ($p in $possible) {
            if (Test-Path $p) {
                return @($p)
            }
        }
    }
    throw "没有找到 Python，也无法自动安装。请安装 Python 3 后重新运行。"
}

function Ensure-GitHubCli {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        return
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "正在安装 GitHub CLI..." -ForegroundColor Yellow
        winget install --id GitHub.cli -e --source winget --accept-source-agreements --accept-package-agreements
        $possible = @(
            "$env:ProgramFiles\GitHub CLI\gh.exe",
            "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
        )
        foreach ($p in $possible) {
            if (Test-Path $p) {
                $env:Path = "$(Split-Path $p);$env:Path"
                break
            }
        }
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 安装失败。请先安装 gh，然后重新运行。"
    }
}

$py = Find-Python
Ensure-GitHubCli

Write-Host "检查 GitHub 登录状态..." -ForegroundColor Yellow
& gh auth status -h github.com *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "需要登录 GitHub。浏览器会自动打开，只需登录你自己的 GitHub 账号。" -ForegroundColor Yellow
    & gh auth login -h github.com -w
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub 登录失败。"
    }
}

$pythonCode = @'
import asyncio
import json
import sys
from pathlib import Path

from playwright.async_api import async_playwright

STATE_PATH = Path(sys.argv[1])

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        context = await browser.new_context(
            locale="zh-CN",
            viewport={"width": 1365, "height": 900},
        )
        page = await context.new_page()
        await page.goto(
            "https://www.xiaohongshu.com/explore",
            wait_until="domcontentloaded",
            timeout=60000,
        )

        print()
        print("请在弹出的浏览器里登录小红书。")
        print("扫码、短信验证码或安全验证都在那个真实浏览器里完成。")
        print("确认首页可以正常看到内容后，回到这个窗口按 Enter。")
        print()

        while True:
            input("登录完成后按 Enter：")
            cookies = await context.cookies()
            cookie_names = {c.get("name", "") for c in cookies}
            body = ""
            try:
                body = (await page.locator("body").inner_text(timeout=5000))[:4000]
            except Exception:
                pass

            has_session = any(
                name in cookie_names
                for name in ("web_session", "a1", "webId", "webBuild")
            )
            looks_logged_out = ("扫码登录" in body or "手机号登录" in body) and not has_session

            if has_session and not looks_logged_out:
                break

            print()
            print("还没有检测到可用登录态。请继续在浏览器完成登录，然后再按 Enter。")
            print()

        state = await context.storage_state()
        STATE_PATH.write_text(
            json.dumps(state, ensure_ascii=False),
            encoding="utf-8",
        )
        await browser.close()

asyncio.run(main())
'@

Set-Content -Path $PyPath -Value $pythonCode -Encoding UTF8

Write-Host "检查 Playwright..." -ForegroundColor Yellow
$pyExe = $py[0]
$pyArgs = @()
if ($py.Count -gt 1) {
    $pyArgs = $py[1..($py.Count - 1)]
}

& $pyExe @pyArgs -c "import playwright" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "首次使用，正在安装 Playwright..." -ForegroundColor Yellow
    & $pyExe @pyArgs -m pip install --user playwright
}

Write-Host "检查 Chromium..." -ForegroundColor Yellow
& $pyExe @pyArgs -m playwright install chromium

Write-Host ""
Write-Host "即将打开小红书登录窗口..." -ForegroundColor Green
& $pyExe @pyArgs $PyPath $StatePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $StatePath)) {
    throw "没有取得小红书登录态。"
}

$raw = Get-Content -Path $StatePath -Raw -Encoding UTF8
$bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
$b64 = [Convert]::ToBase64String($bytes)

Write-Host "正在安全写入 GitHub Actions Secret..." -ForegroundColor Yellow
$b64 | & gh secret set XHS_STORAGE_STATE_B64 --repo $Repo
if ($LASTEXITCODE -ne 0) {
    throw "写入 GitHub Secret 失败。"
}

Write-Host "已更新登录态。现在触发一次房源抓取..." -ForegroundColor Yellow
& gh workflow run mansion-tracker.yml --repo $Repo
if ($LASTEXITCODE -ne 0) {
    Write-Warning "登录态已经保存，但自动触发抓取失败。下一次30分钟任务仍会自动使用新登录态。"
}

Remove-Item $StatePath -Force -ErrorAction SilentlyContinue
Remove-Item $PyPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "完成：小红书登录态已更新。" -ForegroundColor Green
Write-Host "可以关闭这个窗口。App 会在下一次抓取完成后自动更新。"
Write-Host ""
Start-Process $PublicApp
Read-Host "按 Enter 退出"
