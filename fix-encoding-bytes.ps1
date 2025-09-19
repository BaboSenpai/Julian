# fix-encoding-bytes.ps1
# Repair mojibake in lib/ui/screens.dart using byte-safe logic (ASCII-only script).
# - Removes real BOM (EF BB BF)
# - Tries reverse-decode CP1252 and ISO-8859-1
# - Saves as UTF-8 without BOM

$path = Resolve-Path "lib/ui/screens.dart"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# 1) Read bytes
[byte[]]$bytes = [IO.File]::ReadAllBytes($path)

# 2) Strip real UTF-8 BOM (EF BB BF)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
  $bytes = $bytes[3..($bytes.Length-1)]
}

# 3) Decode current bytes as UTF-8 (best-effort)
$text = [Text.Encoding]::UTF8.GetString($bytes)

# 4) Strip in-text BOM (U+FEFF) if present at start
if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

function Score([string]$s) {
  # Count typical mojibake markers by CHAR CODES (no non-ASCII literals):
  $c1 = ($s.ToCharArray() | Where-Object { [int]$_ -eq 0x00C3 }).Count  # 'Ã'
  $c2 = ($s.ToCharArray() | Where-Object { [int]$_ -eq 0x00C2 }).Count  # 'Â'
  $c3 = ($s.ToCharArray() | Where-Object { [int]$_ -eq 0x00F0 }).Count  # 'ð'
  $c4 = ($s.ToCharArray() | Where-Object { [int]$_ -eq 0xFFFD }).Count  # ' ' replacement char
  return ($c1 + $c2 + $c3 + $c4)
}

# 5) Current score
$scoreBefore = Score $text

# 6) Reverse-decode attempts (ASCII-only transformations)
#    Take the current TEXT, encode to CP1252 bytes, then decode as UTF-8
$try1252 = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(1252).GetBytes($text))
$score1252 = Score $try1252

#    Same with ISO-8859-1 (codepage 28591)
$try8859 = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes($text))
$score8859 = Score $try8859

# 7) Choose best variant
$best = $text
$bestScore = $scoreBefore
if ($score1252 -lt $bestScore) { $best = $try1252; $bestScore = $score1252 }
if ($score8859 -lt $bestScore) { $best = $try8859; $bestScore = $score8859 }

# 8) Save as UTF-8 without BOM
[IO.File]::WriteAllText($path, $best, $utf8NoBom)

Write-Host ("Re-encoded: {0}`nScores -> before={1}  cp1252={2}  iso8859={3}" -f $path, $scoreBefore, $score1252, $score8859)

# 9) Flutter tidy (no app start)
flutter clean
flutter pub get

# 10) Git commit + push
git add lib/ui/screens.dart
git commit -m "Fix: re-encode screens.dart to clean UTF-8 (no BOM); reverse-decode CP1252/ISO-8859-1"
git push origin main
