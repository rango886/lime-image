@echo off
setlocal EnableExtensions
for /f "tokens=2 delims=:" %%c in ('chcp') do set "OLDCP=%%c"
chcp 65001 >nul
cd /d "%~dp0"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -File"
set "DIR=%~dp0assoc"
title Lime Image 文件关联

if not exist "%DIR%\register-limeimage.ps1" (
    echo [错误] 找不到 %DIR%\register-limeimage.ps1
    pause & exit /b 1
)
if not "%~1"=="" (set "SEL=%~1" & goto run)

:menu
cls
echo ==========================================================
echo    Lime Image 文件关联    %~dp0lime-image.exe
echo ==========================================================
echo   1  设为默认图片程序   ^(注册 + 写 UserChoice^)
echo   2  取消关联
echo   0  退出
echo ----------------------------------------------------------
set /p "SEL=请选择 [1]: "
if "%SEL%"=="" set "SEL=1"

:run
if "%SEL%"=="1" goto setdefault
if "%SEL%"=="2" goto unreg
if "%SEL%"=="0" exit /b 0
echo 无效选项: %SEL% & timeout /t 2 >nul & goto menu

:setdefault
%PS% "%DIR%\register-limeimage.ps1"    || goto err
%PS% "%DIR%\set-default-limeimage.ps1" || goto err
goto done

:unreg
%PS% "%DIR%\register-limeimage.ps1" -Unregister || goto err
goto done

:done
ie4uinit.exe -show
echo.
echo [完成]
if "%~1"=="" (echo. & set /p "A=按 Enter 返回菜单，输入 q 退出: " & if /i not "%A%"=="q" goto menu)
if defined OLDCP chcp %OLDCP% >nul
exit /b 0

:err
echo.
echo [失败] 上一步返回了错误，请看上面的输出。
pause
if defined OLDCP chcp %OLDCP% >nul
exit /b 1