@echo off
rem ============================================
rem  DSH Mobile 一键启动（双击运行）
rem  1) 启动 DSH web 实例 (127.0.0.1:3081)
rem  2) 启动端口转发 (0.0.0.0:3081 -> 127.0.0.1:3081)
rem  手机访问: http://<本机IP>:3081  (App 里填这个)
rem ============================================
chcp 65001 >nul
cd /d "%~dp0"

echo [1/2] 启动 DSH web 实例 (127.0.0.1:3081) ...
start "DSH Web 3081" cmd /k "D:\Users\Melody\Desktop\日常不用\deepseek-harness-app\node_modules\.bin\dsh.CMD web --host 127.0.0.1 --port 3081 --trusted-host 192.168.1.4:3081"

timeout /t 3 /nobreak >nul

echo [2/2] 启动端口转发 (0.0.0.0:3081) ...
start "DSH Port Forward 3081" cmd /k "node tools\port-forward.mjs 3081 3081"

timeout /t 2 /nobreak >nul
echo.
echo ============================================
echo  启动完成！手机 DSH Mobile 里填:
echo    http://192.168.1.4:3081
echo  （如果电脑 IP 变了，先运行 ipconfig 查看）
echo ============================================
echo.
pause
