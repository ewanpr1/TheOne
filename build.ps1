# Builds the production page TheOne_V6.html from src/TheOne.src.html.
#
#   - Compiles the JSX block once, ahead of time (Babel run inside headless Edge,
#     so no Node/Python is needed), instead of compiling it on every launch on the phone.
#   - Swaps React development builds for the production builds and drops Babel.
#   - Bumps the service-worker cache version so players pick up the new files.
#
# Usage (from the project folder):   powershell -ExecutionPolicy Bypass -File .\build.ps1
# Edit src/TheOne.src.html (it still runs as-is in a browser), then rebuild.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$srcPath = Join-Path $root 'src\TheOne.src.html'
$outPath = Join-Path $root 'TheOne_V6.html'
$swPath  = Join-Path $root 'sw.js'
$utf8 = New-Object System.Text.UTF8Encoding $false

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
          "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge introuvable : il sert à exécuter Babel.' }

$src = [IO.File]::ReadAllText($srcPath, $utf8)
$m = [regex]::Match($src, '(?s)<script type="text/babel">(.*?)</script>')
if (-not $m.Success) { throw 'Bloc <script type="text/babel"> introuvable dans la source.' }
$jsx = $m.Groups[1].Value

# 1) Compile JSX with Babel inside headless Edge; the result comes back base64-encoded in the dumped DOM
$tmp = Join-Path $env:TEMP 'theone-build'
New-Item -ItemType Directory -Force $tmp | Out-Null
$b64 = [Convert]::ToBase64String($utf8.GetBytes($jsx))
$page = @"
<!doctype html><meta charset="utf-8">
<script src="https://unpkg.com/@babel/standalone@7.29.0/babel.min.js"></script>
<pre id="out"></pre>
<script>
try{
  const src=new TextDecoder().decode(Uint8Array.from(atob('$b64'),c=>c.charCodeAt(0)));
  const code=Babel.transform(src,{presets:['react'],comments:false}).code;
  const bytes=new TextEncoder().encode(code);let s='';
  for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode.apply(null,bytes.subarray(i,i+8192));
  document.getElementById('out').textContent='OK:'+btoa(s);
}catch(e){document.getElementById('out').textContent='ERR:'+e.message;}
</script>
"@
[IO.File]::WriteAllText((Join-Path $tmp 'compile.html'), $page, $utf8)
$url = 'file:///' + ($tmp -replace '\\','/') + '/compile.html'
# Edge logs harmless noise on stderr, which Windows PowerShell would turn into a terminating error
$ErrorActionPreference = 'Continue'
$dom = & $edge --headless=new --disable-gpu --no-first-run "--user-data-dir=$tmp\profile" --virtual-time-budget=30000 --dump-dom $url 2>$null | Out-String
$ErrorActionPreference = 'Stop'
$r = [regex]::Match($dom, '<pre id="out">(OK|ERR):([^<]*)</pre>')
if (-not $r.Success) { throw 'Babel n''a rien renvoyé (connexion internet requise pour charger Babel).' }
if ($r.Groups[1].Value -eq 'ERR') { throw "Erreur de compilation : $($r.Groups[2].Value)" }
$js = $utf8.GetString([Convert]::FromBase64String($r.Groups[2].Value))

# 2) Assemble the production page
$out = $src
$out = $out.Replace(
  '<script src="https://unpkg.com/react@18.3.1/umd/react.development.js" integrity="sha384-hD6/rw4ppMLGNu3tX5cjIb+uRZ7UkRJ6BPkLpg4hAu/6onKUg4lLsHAs9EBPT82L" crossorigin="anonymous"></script>',
  '<script src="https://unpkg.com/react@18.3.1/umd/react.production.min.js" integrity="sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z" crossorigin="anonymous"></script>')
$out = $out.Replace(
  '<script src="https://unpkg.com/react-dom@18.3.1/umd/react-dom.development.js" integrity="sha384-u6aeetuaXnQ38mYT8rp6sbXaQe3NL9t+IBXmnYxwkUI2Hw4bsp2Wvmx4yRQF1uAm" crossorigin="anonymous"></script>',
  '<script src="https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js" integrity="sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1" crossorigin="anonymous"></script>')
$out = [regex]::Replace($out, '(?m)^<script src="https://unpkg.com/@babel/standalone[^\n]*\r?\n', '')
$out = $out.Replace($m.Value, "<script>`n$js`n</script>")
$out = $out.Replace('<!DOCTYPE html>', "<!DOCTYPE html>`n<!-- FICHIER GÉNÉRÉ par build.ps1 depuis src/TheOne.src.html : ne pas modifier directement -->")
if ($out -match 'react\.development|@babel/standalone|text/babel') { throw 'Il reste des références de développement dans la sortie.' }
[IO.File]::WriteAllText($outPath, $out, $utf8)

# 3) Bump the service-worker cache version
$sw = [IO.File]::ReadAllText($swPath, $utf8)
$sw = [regex]::Replace($sw, "theone-v(\d+)", { param($mm) 'theone-v' + ([int]$mm.Groups[1].Value + 1) }, 1)
[IO.File]::WriteAllText($swPath, $sw, $utf8)

"OK  $([math]::Round($out.Length/1KB)) Ko -> $outPath"
"Cache SW : " + [regex]::Match($sw, "theone-v\d+").Value
