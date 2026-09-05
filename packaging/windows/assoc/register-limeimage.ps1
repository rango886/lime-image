<#
  lime-image 绿色版：注册 ProgID / 打开方式 / 可设为默认（当前用户，免管理员）
  用法:
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string]$ExePath,
    [string]$AppName = 'Lime Image',
    [string[]]$Extensions = @(
        '.png','.jpg','.jpeg','.jpe','.jfif','.bmp','.dib','.gif','.apng','.webp','.avif','.avifs',
        '.tif','.tiff','.ico','.cur','.heic','.heif','.hif','.jxl','.tga','.icb','.vda','.vst',
        '.psd','.psb','.dds','.exr','.hdr','.j2k','.jp2','.jpf','.jpx','.pam','.pbm','.pgm',
        '.pnm','.ppm','.pcx','.qoi','.rgb','.sgi','.wbmp','.svg','.svgz','.cbz',
        # RAW
        '.3fr','.ari','.arw','.bay','.cap','.cr2','.cr3','.crw','.dcr','.dcs','.dng','.drf',
        '.eip','.erf','.fff','.iiq','.k25','.kdc','.mef','.mos','.mrw','.nef','.nrw','.orf',
        '.ori','.pef','.ptx','.pxn','.raf','.raw','.rw2','.rwl','.sr2','.srf','.srw','.x3f'),
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ExePath) {
    # 脚本在 assoc\ 子目录里，exe 在上级；也兼容脚本与 exe 同目录
    foreach ($c in @((Join-Path $here 'lime-image.exe'),
                     (Join-Path (Split-Path $here -Parent) 'lime-image.exe'))) {
        if (Test-Path $c) { $ExePath = $c; break }
    }
}
if (-not $ExePath) { throw "找不到 lime-image.exe，请用 -ExePath 指定" }
$ExePath   = (Resolve-Path $ExePath).Path
$exeName   = Split-Path $ExePath -Leaf              # lime-image.exe
$classes   = 'HKCU:\Software\Classes'
$appKey    = "$classes\Applications\$exeName"
$capKey    = 'HKCU:\Software\LimeImage\Capabilities'
$progIdOf  = { param($e) 'LimeImage.Assoc.' + $e.TrimStart('.').ToUpper() }   # .png -> LimeImage.Assoc.PNG

function New-Key($p) { if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null } }
function Set-Val($p, $n, $v) { New-Key $p; New-ItemProperty -Path $p -Name $n -Value $v -PropertyType String -Force | Out-Null }

if ($Unregister) {
    foreach ($e in $Extensions) {
        Remove-Item "$classes\$(& $progIdOf $e)" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty "$classes\$e\OpenWithProgids" -Name (& $progIdOf $e) -ErrorAction SilentlyContinue
    }
    Remove-Item $appKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKCU:\Software\LimeImage' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\Software\RegisteredApplications' -Name $AppName -ErrorAction SilentlyContinue
    Write-Host '已注销 lime-image 关联。' -ForegroundColor Yellow
    return
}

# --- 1) Applications\lime-image.exe : 出现在“打开方式”列表 -------------------
Set-Val $appKey 'FriendlyAppName' $AppName
Set-Val "$appKey\shell\open\command" '(default)' "`"$ExePath`" `"%1`""
New-Key "$appKey\SupportedTypes"
foreach ($e in $Extensions) { Set-Val "$appKey\SupportedTypes" $e '' }

# --- 2) 每个扩展名一个 ProgID（默认程序必须靠它）------------------------------
foreach ($e in $Extensions) {
    $progId = & $progIdOf $e
    Set-Val "$classes\$progId" '(default)' "$AppName $($e.TrimStart('.').ToUpper()) File"
    Set-Val "$classes\$progId" 'FriendlyTypeName' "$AppName $($e.TrimStart('.').ToUpper()) File"
    Set-Val "$classes\$progId\DefaultIcon" '(default)' "`"$ExePath`",0"
    Set-Val "$classes\$progId\shell\open\command" '(default)' "`"$ExePath`" `"%1`""
    # 出现在该扩展名的“打开方式”候选中
    Set-Val "$classes\$e\OpenWithProgids" $progId ''
}

# --- 3) Capabilities：让“设置 → 默认应用”能按 App 一次性设置 -----------------
Set-Val $capKey 'ApplicationName'        $AppName
Set-Val $capKey 'ApplicationDescription' '轻量看图工具（绿色版）'
Set-Val $capKey 'ApplicationIcon'        "`"$ExePath`",0"
foreach ($e in $Extensions) { Set-Val "$capKey\FileAssociations" $e (& $progIdOf $e) }
Set-Val 'HKCU:\Software\RegisteredApplications' $AppName 'Software\LimeImage\Capabilities'

Write-Host "注册完成：$ExePath" -ForegroundColor Green
Write-Host "ProgID 示例: $(& $progIdOf '.png')，共 $($Extensions.Count) 个扩展名"
