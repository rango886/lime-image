<#
  lime-image 绿色版：注册 ProgID / 打开方式 / 可设为默认（当前用户，免管理员）
  同时注册右键菜单“批量转换图片”：图片文件、文件夹、文件夹空白处。
  用法:
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1 -NoContextMenu     # 不加右键菜单
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1 -ContextMenuOnly   # 只加右键菜单
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1 -RemoveContextMenu # 只删右键菜单
      powershell -ExecutionPolicy Bypass -File .\register-limeimage.ps1 -Unregister        # 全部撤销（含右键菜单）
  Windows 11 上经典右键菜单在“显示更多选项”（Shift+F10）里。
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
    [switch]$Unregister,
    [switch]$NoContextMenu,
    [switch]$ContextMenuOnly,
    [switch]$RemoveContextMenu,
    [string]$MenuText
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
$removing = $Unregister -or $RemoveContextMenu
if ($ExePath) {
    $ExePath = (Resolve-Path $ExePath).Path
} elseif (-not $removing) {
    # 注销不需要 exe 存在（可能已经先删了程序目录）
    throw "找不到 lime-image.exe，请用 -ExePath 指定"
}
$exeName   = if ($ExePath) { Split-Path $ExePath -Leaf } else { 'lime-image.exe' }
$classes   = 'HKCU:\Software\Classes'
$appKey    = "$classes\Applications\$exeName"
$capKey    = 'HKCU:\Software\LimeImage\Capabilities'
$progIdOf  = { param($e) 'LimeImage.Assoc.' + $e.TrimStart('.').ToUpper() }   # .png -> LimeImage.Assoc.PNG

function New-Key($p) { if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null } }
function Set-Val($p, $n, $v) { New-Key $p; New-ItemProperty -Path $p -Name $n -Value $v -PropertyType String -Force | Out-Null }

# --- 右键菜单：批量转换 -------------------------------------------------------
$verb = 'LimeImage.Batch'
# 压缩包（.cbz）不是单张图片，不进批量菜单
$batchExts = $Extensions | Where-Object { $_ -ne '.cbz' }

function Remove-ContextMenu {
    # 按注册表实际内容清理，扩展名列表改过也能删干净
    $sfa = "$classes\SystemFileAssociations"
    if (Test-Path $sfa) {
        Get-ChildItem $sfa -ErrorAction SilentlyContinue | ForEach-Object {
            $k = "$sfa\$($_.PSChildName)\shell\$verb"
            if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force }
        }
    }
    foreach ($k in "$classes\Directory\shell\$verb", "$classes\Directory\Background\shell\$verb") {
        Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Add-ContextMenu {
    if (-not $MenuText) {
        # 优先跟程序内选的语言（exe 同目录 settings.json），其次是系统显示语言
        $lang = $null
        $cfg = Join-Path (Split-Path $ExePath -Parent) 'settings.json'
        if (Test-Path $cfg) {
            try { $lang = (Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json).language } catch {}
        }
        if (-not $lang) { $lang = (Get-UICulture).Name }
        $MenuText = switch -Wildcard ($lang) {
            'zh-Hant*' { '批次轉換圖片' ; break }
            'zh-TW'    { '批次轉換圖片' ; break }
            'zh-HK'    { '批次轉換圖片' ; break }
            'zh*'      { '批量转换图片' ; break }
            'ja*'      { '画像を一括変換' ; break }
            'ko*'      { '이미지 일괄 변환' ; break }
            default    { 'Batch convert images' ; break }
        }
    }
    function Set-Verb($key, $arg, [switch]$Multi) {
        Set-Val $key 'MUIVerb' $MenuText
        # 不显示图标；清掉旧版本写入的 Icon 值
        Remove-ItemProperty -LiteralPath $key -Name 'Icon' -ErrorAction SilentlyContinue
        # 默认（Document）超过 15 个选中项菜单会消失；Player 不限数量。
        # Explorer 仍按文件各起一个进程，由 exe 的单实例端口合并到同一窗口。
        if ($Multi) { Set-Val $key 'MultiSelectModel' 'Player' }
        Set-Val "$key\command" '(default)' "`"$ExePath`" --batch `"$arg`""
    }
    foreach ($e in $batchExts) {
        Set-Verb "$classes\SystemFileAssociations\$e\shell\$verb" '%1' -Multi
    }
    Set-Verb "$classes\Directory\shell\$verb" '%1' -Multi
    # 空白处没有选中项，用 %V（当前文件夹）
    Set-Verb "$classes\Directory\Background\shell\$verb" '%V'
    Write-Host "右键菜单已添加：$MenuText（图片 $($batchExts.Count) 种 + 文件夹 + 文件夹空白处）"
}

if ($Unregister) {
    Remove-ContextMenu
    foreach ($e in $Extensions) {
        Remove-Item "$classes\$(& $progIdOf $e)" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty "$classes\$e\OpenWithProgids" -Name (& $progIdOf $e) -ErrorAction SilentlyContinue
    }
    Remove-Item $appKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKCU:\Software\LimeImage' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\Software\RegisteredApplications' -Name $AppName -ErrorAction SilentlyContinue
    Write-Host '已注销 lime-image 关联和右键菜单。' -ForegroundColor Yellow
    return
}

if ($RemoveContextMenu) {
    Remove-ContextMenu
    Write-Host '已移除右键菜单。' -ForegroundColor Yellow
    return
}

if ($ContextMenuOnly) {
    Remove-ContextMenu
    Add-ContextMenu
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

# --- 4) 右键菜单 ---------------------------------------------------------------
Remove-ContextMenu
if (-not $NoContextMenu) { Add-ContextMenu }

Write-Host "注册完成：$ExePath" -ForegroundColor Green
Write-Host "ProgID 示例: $(& $progIdOf '.png')，共 $($Extensions.Count) 个扩展名"
