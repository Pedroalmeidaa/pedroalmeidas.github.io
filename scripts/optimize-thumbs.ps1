# optimize-thumbs.ps1
# Otimiza os videos em assets/thumbs/*.mp4 gerando:
#   - <nome>.webm  (VP9, ~500kbps, sem audio, 5s, 720p)
#   - <nome>.mp4   (H.264 reotimizado, faststart, sem audio, 5s, 720p)
#   - <nome>.webp  (poster do primeiro frame, ~80% qualidade)
#
# Os arquivos sao gravados em assets/thumbs/optimized/ para nao sobrescrever os originais.
# Apos validar visualmente, mova de optimized/ para thumbs/ ou ajuste o caminho no HTML.
#
# Pre-requisito: ffmpeg no PATH (winget install ffmpeg).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\optimize-thumbs.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root 'assets\thumbs'
$outDir = Join-Path $srcDir 'optimized'

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  Write-Host "ffmpeg nao encontrado no PATH. Instale: winget install ffmpeg" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir | Out-Null
}

$videos = Get-ChildItem -Path $srcDir -Filter '*.mp4' -File
if ($videos.Count -eq 0) {
  Write-Host "Nenhum .mp4 encontrado em $srcDir" -ForegroundColor Yellow
  exit 0
}

# Parametros do encode (mantem a duracao original do video)
$SCALE    = 'scale=720:-2'
$FPS      = 24
$VP9_BR   = '500k'    # bitrate alvo VP9
$H264_CRF = 28        # CRF H.264 (quanto maior, menor o arquivo)
$WEBP_Q   = 80        # qualidade do poster

$totalBefore = 0
$totalAfter  = 0

foreach ($v in $videos) {
  $name = [System.IO.Path]::GetFileNameWithoutExtension($v.Name)
  $webm = Join-Path $outDir "$name.webm"
  $mp4  = Join-Path $outDir "$name.mp4"
  $webp = Join-Path $outDir "$name.webp"

  Write-Host ""
  Write-Host "==> $($v.Name)" -ForegroundColor Cyan
  $totalBefore += $v.Length

  # 1) WebM (VP9, 2-pass dispensado para velocidade; CRF + bitrate alvo)
  & ffmpeg -y -hide_banner -loglevel error `
    -i $v.FullName `
    -vf "$SCALE,fps=$FPS" `
    -c:v libvpx-vp9 -b:v $VP9_BR -crf 33 -row-mt 1 `
    -an $webm

  # 2) MP4 H.264 (fallback Safari) - faststart para inicio rapido
  & ffmpeg -y -hide_banner -loglevel error `
    -i $v.FullName `
    -vf "$SCALE,fps=$FPS" `
    -c:v libx264 -crf $H264_CRF -preset slow -pix_fmt yuv420p `
    -movflags +faststart `
    -an $mp4

  # 3) Poster WebP do primeiro frame
  & ffmpeg -y -hide_banner -loglevel error `
    -i $v.FullName `
    -vf "$SCALE,select=eq(n\,0)" -vframes 1 `
    -c:v libwebp -quality $WEBP_Q $webp

  $sizes = @(
    (Get-Item $webm).Length,
    (Get-Item $mp4).Length,
    (Get-Item $webp).Length
  )
  $sumNew = ($sizes | Measure-Object -Sum).Sum
  $totalAfter += $sumNew

  $orig = '{0:N1} MB' -f ($v.Length / 1MB)
  $newW = '{0:N0} KB' -f ($sizes[0] / 1KB)
  $newM = '{0:N0} KB' -f ($sizes[1] / 1KB)
  $newP = '{0:N0} KB' -f ($sizes[2] / 1KB)
  Write-Host "    original $orig  ->  webm $newW | mp4 $newM | webp $newP"
}

$mbBefore = '{0:N1}' -f ($totalBefore / 1MB)
$mbAfter  = '{0:N1}' -f ($totalAfter / 1MB)
$pct      = '{0:N0}' -f ((1 - $totalAfter / $totalBefore) * 100)

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "Total original : $mbBefore MB"
Write-Host "Total novo     : $mbAfter MB  ($pct% reducao)"
Write-Host "Arquivos em    : $outDir"
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Proximo passo: validar visualmente e mover de 'optimized/' para 'assets/thumbs/'."
Write-Host "Se mover, os arquivos antigos serao sobrescritos. Faca commit antes."
