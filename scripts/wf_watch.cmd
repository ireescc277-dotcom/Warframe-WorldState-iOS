@echo off
rem 后台盯住 AlecaFrame 的 lastData.dat，一变就重建并推 VPS。
rem 双击即可；要停就打开任务管理器结束 pythonw.exe。
rem 日志在 data\watch.log。
cd /d "%~dp0.."
start "" "C:\Python314\pythonw.exe" "scripts\wf_watch.py"
