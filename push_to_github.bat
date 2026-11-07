@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo       WarframeWatch GitHub Push & Build Helper
echo ========================================================
echo.

set /p REPO_URL="Enter your GitHub repository URL (e.g. https://github.com/yourname/WarframeWatch.git): "
if "%REPO_URL%"=="" (
    echo Error: Repository URL cannot be empty.
    pause
    exit /b 1
)

"C:\Program Files\Git\cmd\git.exe" remote remove origin 2>nul
"C:\Program Files\Git\cmd\git.exe" remote add origin %REPO_URL%
"C:\Program Files\Git\cmd\git.exe" branch -M main
echo Pushing to GitHub...
"C:\Program Files\Git\cmd\git.exe" push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================================
    echo  Successfully pushed to GitHub!
    echo  GitHub Actions will automatically start compiling
    echo  your unsigned IPA. Go to the Actions tab on GitHub
    echo  to download WarframeWatch-unsigned.ipa when done!
    echo ========================================================
) else (
    echo.
    echo Push failed. Please verify your repository URL and credentials.
)

pause
