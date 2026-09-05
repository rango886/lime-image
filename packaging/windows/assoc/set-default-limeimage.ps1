<#
  把已注册的 LimeImage.Assoc.* 全部设为默认（写 UserChoice + 合法 Hash）
  依赖同目录的 SFTA.ps1（来自 PS-SFTA，纯 PowerShell，全程离线、免管理员）
  扩展名自动从注册表里的 LimeImage.Assoc.* 推导，与 register-limeimage.ps1 保持一致。
      -Only .jpg,.png    只设置指定扩展名
#>
param([string[]]$Only)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition

$sfta = Join-Path $here 'SFTA.ps1'
if (-not (Test-Path $sfta)) {
    throw "缺少 $sfta（本脚本不联网）。请从 PS-SFTA 项目手动下载 SFTA.ps1 放到此目录。"
}
. $sfta

$map = @{}
Get-ChildItem 'HKCU:\Software\Classes' | Where-Object PSChildName -like 'LimeImage.Assoc.*' | ForEach-Object {
    $map['.' + $_.PSChildName.Substring(16).ToLower()] = $_.PSChildName
}
if ($Only) {
    $f = @{}; foreach ($k in $Only) { if ($map.ContainsKey($k)) { $f[$k] = $map[$k] } }; $map = $f
}
if ($map.Count -eq 0) { throw '没找到已注册的 LimeImage.Assoc.*，请先跑 register-limeimage.ps1' }

$ok = 0; $fail = @()
foreach ($e in ($map.Keys | Sort-Object)) {
    try   { Set-FTA -ProgId $map[$e] -Extension $e; $ok++ }
    catch { $fail += "$e ($($_.Exception.Message))" }
}
Write-Host "已设为默认: $ok / $($map.Count)" -ForegroundColor Green
if ($fail) { Write-Warning ("失败: " + ($fail -join '; ')) }
