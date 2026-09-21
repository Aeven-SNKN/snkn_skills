<#
.SYNOPSIS
  Extract the heading/list outline from a Word .docx so it can be mapped to an
  Azure DevOps work-item hierarchy.

.DESCRIPTION
  A .docx is a ZIP archive whose text lives in word/document.xml. This script
  reads that part, splits it into paragraphs, and labels each paragraph by its
  style so the heading hierarchy (Heading1/2/3...) and list items are visible.

.PARAMETER Path
  Full path to the .docx file.

.PARAMETER OutFile
  Optional path to write the outline to (UTF-8). If omitted, prints to stdout.

.EXAMPLE
  ./extract-docx-outline.ps1 -Path "C:\docs\tender.docx" -OutFile "C:\docs\_outline.txt"
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$OutFile
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
    if (-not $entry) { throw "word/document.xml not found - is this a valid .docx?" }
    $reader = New-Object System.IO.StreamReader($entry.Open())
    $xml = $reader.ReadToEnd()
    $reader.Close()
}
finally {
    $zip.Dispose()
}

$sb = New-Object System.Text.StringBuilder
foreach ($p in [regex]::Matches($xml, '<w:p[ >].*?</w:p>')) {
    $blk = $p.Value
    $style = [regex]::Match($blk, '<w:pStyle w:val="([^"]+)"').Groups[1].Value
    $text = ([regex]::Replace($blk, '<[^>]+>', '')).Trim()
    if ($text -eq '') { continue }
    if ($style -match '^Heading(\d)') { [void]$sb.AppendLine("[H$($Matches[1])] $text") }
    elseif ($style -match 'ListParagraph|List') { [void]$sb.AppendLine("   - $text") }
    else { [void]$sb.AppendLine($text) }
}

$outline = $sb.ToString()
if ($OutFile) {
    $outline | Out-File -FilePath $OutFile -Encoding utf8
    Write-Output "Saved outline to: $OutFile"
}
else {
    Write-Output $outline
}
