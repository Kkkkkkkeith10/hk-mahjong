@echo off
rem One-click upload of the compiled engine + fan table to Supabase Storage
rem (bucket 'mj'). Output lands in upload_assets.log.
cd /d "%~dp0"
rem Reads MP_BASE_URL and MP_UPLOAD_KEY from mj_core\.env (git-ignored; see .env.example).
if not exist .env (echo Missing .env - copy .env.example & exit /b 1)
for /f "usebackq eol=# tokens=1,* delims==" %%a in (".env") do set "%%a=%%b"
set URL=%MP_BASE_URL%/storage/v1/object/mj
set KEY=%MP_UPLOAD_KEY%
echo === upload mj.wasm === > upload_assets.log
curl -s -X POST "%URL%/mj.wasm" -H "Authorization: Bearer %KEY%" -H "apikey: %KEY%" -H "x-upsert: true" -H "Content-Type: application/wasm" --data-binary "@build\wasm\mj.wasm" >> upload_assets.log 2>&1
echo. >> upload_assets.log
echo === upload mj.mjs === >> upload_assets.log
curl -s -X POST "%URL%/mj.mjs" -H "Authorization: Bearer %KEY%" -H "apikey: %KEY%" -H "x-upsert: true" -H "Content-Type: text/javascript" --data-binary "@build\wasm\mj.mjs" >> upload_assets.log 2>&1
echo. >> upload_assets.log
echo === upload fan_table.json === >> upload_assets.log
curl -s -X POST "%URL%/fan_table.json" -H "Authorization: Bearer %KEY%" -H "apikey: %KEY%" -H "x-upsert: true" -H "Content-Type: application/json" --data-binary "@..\data\fan_table.json" >> upload_assets.log 2>&1
echo. >> upload_assets.log
echo === done === >> upload_assets.log
exit
