# Capture-outcome gate, ported from HealthTracker's R21.5 gate (HT-D51).
#
# "Exactly one outcome, in view without scrolling" is a LAYOUT claim, so it is
# measured as one. A string gate can prove the modal rendered; only a viewport can
# prove it was READABLE without hunting for it.
#
# Measured against the real index.html, driven through the shipped capture path
# with fetch stubbed and a SYNTHETIC vision contract installed (the real one is
# unruled, D1), at two phone sizes and one desktop:
#   * exactly ONE outcome state exists, and the capture surface carries none of it;
#   * SUCCESS -- the first result row and BOTH footer actions are fully inside the
#     viewport with the page unscrolled, and stay there when the result is long
#     enough to scroll the body;
#   * FAILURE -- the stated message and both ways out are in view;
#   * PENDING -- the counted spinner and the cancel are in view.
#
# Unlike the data-layer suite this runs in REAL time, so it exercises the
# createImageBitmap decoder that never settles under --virtual-time-budget (HT-D47).
#
# Scope (D1): the browser profile lives under tests/.tmp, never %TEMP%. Ports differ
# from HealthTracker's gate so both suites can run on one machine.
#
# Exit 0 PASS, 1 FAIL, 2 environment error.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$port = 8237
$origin = "http://127.0.0.1:$port"
$dbg = 9447
$script:cid = 0
$ws = $null
$chrome = $null
$server = $null
$tmpRoot = Join-Path $PSScriptRoot '.tmp'
if (-not (Test-Path $tmpRoot)) { New-Item -ItemType Directory -Force $tmpRoot | Out-Null }
$udd = Join-Path $tmpRoot ("outcome-" + [System.Guid]::NewGuid().ToString('N'))
$ct = [Threading.CancellationToken]::None

$MIN_ACTION_H = 44   # a primary action is a thumb target, not a link

function Find-Browser {
  foreach ($c in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) { if (Test-Path $c) { return $c } }
  return $null
}
function Receive-One {
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 16384
  while ($true) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    $ms.Write($buf, 0, $res.Count)
    if ($res.EndOfMessage) { break }
  }
  return ([Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json)
}
function Invoke-CDP([string]$method, [hashtable]$prms) {
  $script:cid++
  $payload = @{ id = $script:cid; method = $method }
  if ($prms) { $payload.params = $prms }
  $json = $payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
  $guard = 0
  while ($true) {
    if (++$guard -gt 300) { throw "CDP: no response for $method" }
    $msg = Receive-One
    if (($null -ne $msg.id) -and ($msg.id -eq $script:cid)) { return $msg }
  }
}
function Eval([string]$expr) {
  $r = Invoke-CDP 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  return $r.result.result.value
}

# ---- the page-side helpers, installed once per navigation -------------------
$install = @'
(function(){
  window.__g = {};
  __g.rect = function(sel, root){
    var e = (root||document).querySelector(sel);
    if (!e) return { found:false, inView:false };
    var r = e.getBoundingClientRect();
    return { found:true, top:Math.round(r.top), bottom:Math.round(r.bottom),
             w:Math.round(r.width), h:Math.round(r.height),
             inView: (r.top >= -1 && r.bottom <= window.innerHeight + 1 &&
                      r.left >= -1 && r.right <= window.innerWidth + 1 &&
                      r.width > 0 && r.height > 0) };
  };
  __g.contract = { version: 9, acceptLabel: 'Use this', prompt: 'GATE CONTRACT',
    parse: function (t) { var o; try { o = JSON.parse(CT.cleanJSON(t)); } catch (e) { return { ok:false, error:'Bad JSON' }; }
      return (o && typeof o.probe === 'string') ? { ok:true, value:o } : { ok:false, error:'Expected probe' }; },
    accept: function () { return { ok:true }; } };
  __g.snap = function(){
    var w = document.getElementById('captureOutcome');
    var foot = document.getElementById('outcomeFoot');
    var body = document.getElementById('outcomeBody');
    var cap = document.getElementById('captureBox');
    var shown = !!w && w.style.display !== 'none' && w.style.display !== '';
    return {
      state: CT.captureOutcomeState(),
      shown: shown,
      msgText: (document.getElementById('outcomeMsg').textContent || ''),
      lead:   __g.rect('#captureResult .kv'),
      primary:__g.rect('#outcomeFoot .btn:nth-of-type(1)'),
      second: __g.rect('#outcomeFoot .btn:nth-of-type(2)'),
      nActions: document.querySelectorAll('#outcomeFoot .btn').length,
      spin:   __g.rect('#outcomeMsg .byokspin'),
      bodyScrolls: !!body && body.scrollHeight > body.clientHeight + 1,
      pageScrollY: Math.round(window.scrollY || 0),
      pageOverflowX: document.documentElement.scrollWidth > window.innerWidth + 1,
      captureSurfaceClean: !cap || (cap.innerHTML.indexOf('opend') < 0 && cap.innerHTML.indexOf('byokCancel') < 0 &&
                                    cap.innerHTML.indexOf('captureAccept') < 0 && cap.innerHTML.indexOf('captureRetry') < 0),
      footHTML: foot ? foot.innerHTML : ''
    };
  };
  __g.key = function(){ CT.setVisionContract(__g.contract); CT.credClear('vision'); CT.credSave('vision','grok','xai-GATEKEY-0123456789012345',20); };
  __g.file = function(){
    var c=document.createElement('canvas'); c.width=1400; c.height=1050;
    var x=c.getContext('2d'); var g=x.createLinearGradient(0,0,1400,1050);
    g.addColorStop(0,'#873'); g.addColorStop(1,'#39a'); x.fillStyle=g; x.fillRect(0,0,1400,1050);
    return new Promise(function(r){ c.toBlob(function(b){ r(new File([b],'cover.jpg',{type:'image/jpeg'})); },'image/jpeg',0.9); });
  };
  __g.reply = function(n){
    var o = { probe: 'gate' };
    for (var i=0;i<n;i++) o['field_' + (i+1)] = 'value ' + (i+1);
    return JSON.stringify({choices:[{message:{content:JSON.stringify(o)}}]});
  };
  __g.ok = function(n){ window.fetch=function(){ return Promise.resolve({ok:true,status:200,
    text:function(){ return Promise.resolve(__g.reply(n)); }}); }; };
  __g.hang = function(){ window.fetch=function(u,i){ return new Promise(function(_,rej){
    var s=i&&i.signal; if(s) s.addEventListener('abort',function(){ var e=new Error('a'); e.name='AbortError'; rej(e); }); }); }; };
  return 'installed';
})()
'@

$capture = @'
(function(){
  CT.captureDiscard(); CT.byokBusyClear(); __g.key();
  return __g.file().then(function(f){ return CT.byokCapture(f); }).then(function(){ return JSON.stringify(__g.snap()); });
})()
'@

function Go([int]$w, [int]$h, [bool]$mobile) {
  Invoke-CDP 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $mobile } | Out-Null
  Invoke-CDP 'Emulation.setTouchEmulationEnabled' @{ enabled = $mobile; maxTouchPoints = 5 } | Out-Null
  Invoke-CDP 'Page.navigate' @{ url = "$origin/" } | Out-Null
  Start-Sleep -Milliseconds 1500
  Eval $install | Out-Null
}
function Measure-Success([int]$fields) {
  Eval ("__g.ok($fields)") | Out-Null
  return (Eval $capture | ConvertFrom-Json)
}
function Measure-Fail {
  Eval '__g.hang()' | Out-Null
  Eval 'CT.setCallTimeout(2000)' | Out-Null
  $r = Eval $capture | ConvertFrom-Json
  Eval 'CT.setCallTimeout(120000)' | Out-Null
  return $r
}
function Measure-Pending {
  Eval '__g.hang()' | Out-Null
  Eval 'CT.setCallTimeout(120000)' | Out-Null
  Eval '(function(){ CT.captureDiscard(); CT.byokBusyClear(); __g.key();
        __g.file().then(function(f){ window.__p = CT.byokCapture(f); }); return 1; })()' | Out-Null
  Start-Sleep -Milliseconds 1600
  $r = Eval '(function(){ return JSON.stringify(__g.snap()); })()' | ConvertFrom-Json
  Eval '(function(){ CT.byokCancel(); return 1; })()' | Out-Null
  return $r
}

$browser = Find-Browser
if (-not $browser) { Write-Host "ERROR: no Chrome/Edge found"; exit 2 }

$server = Start-Job -ArgumentList $repo, $port -ScriptBlock {
  param($repo, $port)
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://127.0.0.1:$port/")
  $l.Start()
  $mimes = @{ '.html' = 'text/html'; '.js' = 'application/javascript'; '.json' = 'application/json'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.css' = 'text/css' }
  while ($l.IsListening) {
    try { $ctx = $l.GetContext() } catch { break }
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
      $full = Join-Path $repo $rel
      if (Test-Path $full -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        $ext = [System.IO.Path]::GetExtension($full).ToLower()
        if ($mimes.ContainsKey($ext)) { $ctx.Response.ContentType = $mimes[$ext] }
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      } else { $ctx.Response.StatusCode = 404 }
    } catch { }
    try { $ctx.Response.Close() } catch { }
  }
}

function Cleanup {
  try { if ($ws) { $ws.Dispose() } } catch { }
  try { if ($chrome) { Stop-Process -Id $chrome.Id -Force -ErrorAction SilentlyContinue } } catch { }
  try { Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$udd*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
  try { Stop-Job $server -ErrorAction SilentlyContinue; Remove-Job $server -Force -ErrorAction SilentlyContinue } catch { }
  try { Start-Sleep -Milliseconds 400; if (Test-Path $udd) { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}

try {
  Start-Sleep -Milliseconds 800
  try { Invoke-WebRequest "$origin/index.html" -UseBasicParsing -TimeoutSec 5 | Out-Null }
  catch { Write-Host "ERROR: test server did not start"; Cleanup; exit 2 }

  $cargs = @('--headless=new', '--disable-gpu', '--no-sandbox', "--user-data-dir=$udd", '--no-first-run',
             "--remote-debugging-port=$dbg", '--remote-allow-origins=*', 'about:blank')
  $chrome = Start-Process $browser -PassThru -ArgumentList $cargs

  $wsUrl = $null
  for ($i = 0; $i -lt 50; $i++) {
    Start-Sleep -Milliseconds 300
    try {
      $targets = Invoke-RestMethod "http://127.0.0.1:$dbg/json" -TimeoutSec 2
      $pg = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
      if ($pg -and $pg.webSocketDebuggerUrl) { $wsUrl = $pg.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $wsUrl) { Write-Host "ERROR: could not reach Chrome debugging endpoint"; Cleanup; exit 2 }

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$wsUrl, $ct).GetAwaiter().GetResult()
  Invoke-CDP 'Page.enable' $null    | Out-Null
  Invoke-CDP 'Runtime.enable' $null | Out-Null

  $viewports = @(@('phone 360x690', 360, 690, $true), @('phone 390x745', 390, 745, $true), @('desktop 1200x900', 1200, 900, $false))

  Write-Host "capture outcome (real index.html, shipped capture path, CDP, real time):"
  $allOk = $true
  foreach ($v in $viewports) {
    $name = $v[0]; $w = $v[1]; $h = $v[2]; $mob = $v[3]
    Go $w $h $mob

    $S = Measure-Success 2
    $sOk = $S.state -eq 'success' -and $S.shown -and $S.lead.inView -and
           $S.primary.inView -and $S.second.inView -and
           $S.primary.h -ge $MIN_ACTION_H -and $S.second.h -ge $MIN_ACTION_H -and
           $S.footHTML -like '*captureAccept()*' -and $S.footHTML -like '*captureDiscard()*' -and
           $S.nActions -eq 2 -and $S.captureSurfaceClean -and (-not $S.pageOverflowX) -and $S.pageScrollY -eq 0
    Write-Host ("  {0,-17} success : row={1} use={2}({3}px) discard={4} bodyScrolls={5} oneState={6} -> {7}" -f `
      $name, $S.lead.inView, $S.primary.inView, $S.primary.h, $S.second.inView, $S.bodyScrolls, $S.captureSurfaceClean, $sOk)

    # LONG result -- the footer must not travel with the content.
    $L = Measure-Success 30
    $lOk = $L.state -eq 'success' -and $L.shown -and $L.bodyScrolls -and
           $L.primary.inView -and $L.second.inView -and $L.lead.inView -and
           (-not $L.pageOverflowX) -and $L.pageScrollY -eq 0
    Write-Host ("  {0,-17} long    : bodyScrolls={1} use={2} discard={3} row={4} -> {5}" -f `
      $name, $L.bodyScrolls, $L.primary.inView, $L.second.inView, $L.lead.inView, $lOk)

    $F = Measure-Fail
    $fOk = $F.state -eq 'error' -and $F.shown -and $F.primary.inView -and $F.second.inView -and
           $F.footHTML -like '*captureRetry()*' -and $F.footHTML -like '*capturePasteInstead()*' -and
           $F.msgText -like '*did not answer*' -and $F.msgText -like '*still counted*' -and
           $F.nActions -eq 2 -and $F.captureSurfaceClean
    Write-Host ("  {0,-17} failure : msg='{1}' retry={2} paste={3} -> {4}" -f `
      $name, ($F.msgText -replace '\s+', ' ').Substring(0, [Math]::Min(52, $F.msgText.Length)), $F.primary.inView, $F.second.inView, $fOk)

    $P = Measure-Pending
    $pOk = $P.state -eq 'pending' -and $P.shown -and $P.spin.inView -and
           $P.primary.inView -and $P.footHTML -like '*byokCancel*' -and
           $P.msgText -match '\d+s' -and $P.nActions -eq 1 -and $P.captureSurfaceClean
    Write-Host ("  {0,-17} pending : spinner={1} counted='{2}' cancel={3} -> {4}" -f `
      $name, $P.spin.inView, ($P.msgText -replace '[^0-9]*(\d+s).*', '$1'), $P.primary.inView, $pOk)

    if (-not ($sOk -and $lOk -and $fOk -and $pOk)) { $allOk = $false }
  }

  Write-Host ("  thresholds        : exactly one outcome state; first result row and BOTH actions fully inside the viewport with the page unscrolled; actions >={0}px tall; footer fixed while the body scrolls; capture surface carries no outcome" -f $MIN_ACTION_H)
  Write-Host "-----------------------------------------"
  if ($allOk) {
    Write-Host "CAPTURE OUTCOME GATE: PASS (one explicit state per capture, in view without scrolling, at every width)"
    Cleanup; exit 0
  }
  Write-Host "CAPTURE OUTCOME GATE: FAIL"
  Cleanup; exit 1
}
catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Cleanup; exit 2
}
