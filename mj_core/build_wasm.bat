@echo off
rem One-click wasm build of the multiplayer engine wrapper; output lands in
rem build\wasm\ and the full compiler log in build_wasm.log.
cd /d "%~dp0"
echo === dart compile wasm === > build_wasm.log
if not exist build\wasm mkdir build\wasm
call dart compile wasm bin\wasm_api.dart -o build\wasm\mj.wasm >> build_wasm.log 2>&1
echo === exit %ERRORLEVEL% === >> build_wasm.log
dir build\wasm >> build_wasm.log
exit
