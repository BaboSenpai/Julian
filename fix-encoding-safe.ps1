# fix-encoding-safe.ps1
# Repair mojibake in lib/ui/screens.dart by re-decoding (CP1252/ISO-8859-1 -> UTF-8)
# Save as UTF-8 without BOM. Script contains only ASCII.

$path = Resolve-Path "lib/ui/screens.dart"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 1) Read file
$text = Get-Content -Raw -Path $path

# 2) Strip in-text BOM (U+FEFF) if present
if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
if ($text.StartsWith("ï»¿")) { $text = $text.Substring(3) }

# 3) Scoring heuristic for mojibake
function Score([string]$s){
  ($s -split 'Ã').Count + ($s -split 'Â').Count + ($s -split 'ð').Count + ($s -split ' ').Count
}
$scoreBefore = Score $text

# 4) Reverse-decode: CP1252 -> UTF8
$decoded1252 = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(1252).GetBytes($text))
$score1252 = Score $decoded1252

# 5) Reverse-decode: ISO-8859-1 (28591) -> UTF8
$decoded8859 = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes($text))
$score8859 = Score $decoded8859

# 6) Pick best variant
$best = $text
$bestScore = $scoreBefore
if ($score1252 -lt $bestScore) { $best = $decoded1252; $bestScore = $score1252 }
if ($score8859 -lt $bestScore) { $best = $decoded8859; $bestScore = $score8859 }

# 7) Save as UTF-8 without BOM
[IO.File]::WriteAllText($path, $best, $utf8NoBom)

# 8) Remove real byte BOM (EF BB BF) if present
$bytes = [IO.File]::ReadAllBytes($path)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  [IO.File]::WriteAllBytes($path, $bytes[3..($bytes.Length-1)])
}

Write-Host "Re-encoded to clean UTF-8 (no BOM): $path  |  Score before=$scoreBefore, cp1252=$score1252, iso8859=$score8859"

# 9) Flutter tidy (no app start)
flutter clean
flutter pub get

# 10) Git commit + push
git add lib/ui/screens.dart
git commit -m "Fix: re-encode screens.dart to clean UTF-8 without BOM (reverse CP1252/ISO-8859-1)"
git push origin main
