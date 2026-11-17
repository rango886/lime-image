<#
  Lime Image 文件关联菜单（由 setup.bat 调用）。
  菜单放在 PowerShell 里而不是 bat：cmd 在 chcp 65001 下解析含中文的行会错位，
  导致整行被拆开当命令执行。所以 setup.bat 只保留纯 ASCII。
  用法: setup.bat [1|2|3|4]   不带参数时显示菜单
#>
param([string]$Choice)

$here   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$root   = Split-Path -Parent $here
$reg    = Join-Path $here 'register-limeimage.ps1'
$setDef = Join-Path $here 'set-default-limeimage.ps1'
$exe    = Join-Path $root 'lime-image.exe'
$host.UI.RawUI.WindowTitle = 'Lime Image 文件关联'

function Invoke-Step([string]$script, [string[]]$extra = @()) {
    # Out-Host：子脚本输出直接上屏，不混进返回值
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script @extra | Out-Host
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Choice([string]$sel) {
    switch ($sel) {
        '1' { (Invoke-Step $reg) -and (Invoke-Step $setDef) }
        '2' { Invoke-Step $reg @('-Unregister') }
        '3' { Invoke-Step $reg @('-ContextMenuOnly') }
        '4' { Invoke-Step $reg @('-RemoveContextMenu') }
        default { $null }
    }
}

function Finish([bool]$ok) {
    if ($ok) {
        & ie4uinit.exe -show 2>$null
        Write-Host ''
        Write-Host '[完成]' -ForegroundColor Green
    } else {
        Write-Host ''
        Write-Host '[失败] 上一步返回了错误，请看上面的输出。' -ForegroundColor Red
    }
}

# 带参数：直接执行，不显示菜单
if ($Choice) {
    $r = Invoke-Choice $Choice
    if ($null -eq $r) { Write-Host "无效选项: $Choice" -ForegroundColor Red; exit 2 }
    Finish $r
    exit ([int](-not $r))
}

while ($true) {
    Clear-Host
    Write-Host '=========================================================='
    Write-Host "   Lime Image 文件关联    $exe"
    Write-Host '=========================================================='
    Write-Host '  1  设为默认图片程序   (注册 + 写 UserChoice + 右键批量转换)'
    Write-Host '  2  取消关联         (含右键菜单)'
    Write-Host '  3  只添加右键菜单「批量转换图片」'
    Write-Host '  4  只移除右键菜单'
    Write-Host '  0  退出'
    Write-Host '----------------------------------------------------------'
    $sel = (Read-Host '请选择 [1]').Trim()
    if (-not $sel) { $sel = '1' }
    if ($sel -eq '0') { exit 0 }

    $r = Invoke-Choice $sel
    if ($null -eq $r) {
        Write-Host "无效选项: $sel" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        continue
    }
    Finish $r
    if (-not $r) { Read-Host '按 Enter 退出' | Out-Null; exit 1 }
    Write-Host ''
    $a = Read-Host '按 Enter 返回菜单，输入 q 退出'
    if ($a -eq 'q') { exit 0 }
}