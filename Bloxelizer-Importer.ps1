# Bloxelizer Function Importer - Configurable edition
# The first launch asks for the Minecraft datapack function folder and stores
# that setting next to this script. No Minecraft path is hard-coded.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.Windows.Forms.Application]::EnableVisualStyles()

$namespace = 'bloxelizer'
$settingsPath = Join-Path $PSScriptRoot 'Bloxelizer Importer.settings.json'

function Show-Error([string]$message) {
    [void][Windows.Forms.MessageBox]::Show($message, 'Bloxelizer Function Importer', 'OK', 'Error')
}

function Choose-DestinationFolder {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Minecraft datapack function folder (the folder containing .mcfunction files).'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -ne 'OK') { return $null }
    return $dialog.SelectedPath
}

function Load-Destination {
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            if ($settings.Destination -and (Test-Path -LiteralPath $settings.Destination -PathType Container)) {
                return $settings.Destination
            }
        } catch { }
    }
    $selected = Choose-DestinationFolder
    if ([string]::IsNullOrWhiteSpace($selected)) { return $null }
    @{ Destination = $selected } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    return $selected
}

function Normalize-StructureName([string]$value) {
    if ($null -eq $value) { return '' }
    ([regex]::Replace($value.Trim().ToLowerInvariant(), '[^a-z0-9_.-]+', '_')).Trim('_')
}

function Get-FunctionFiles([string]$root) {
    @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.mcfunction')
}

function Get-ExportFiles([System.IO.FileInfo[]]$files) {
    @($files | Where-Object { $_.Name -match '^creation(?:_[0-9]+)?\.mcfunction$' } | Sort-Object Name)
}

function Convert-EntityMarker([string]$line, [ref]$converted) {
    $pattern = '^setblock\s+(\S+)\s+(\S+)\s+(\S+)\s+([a-z0-9_.:-]+)\[__entity=1,__nbt=([^,]+),__src=[^,]+,pitch=([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)),yaw=([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))\]\s*$'
    if ($line -notmatch $pattern) { return $false }
    $x=$Matches[1]; $y=$Matches[2]; $z=$Matches[3]; $entity=$Matches[4]; $pitch=$Matches[6]; $yaw=$Matches[7]
    if ($entity.IndexOf(':') -lt 0) { $entity = "minecraft:$entity" }
    if ($entity -notmatch '^[a-z0-9_.-]+:[a-z0-9_.-]+$') { throw "Invalid Bloxelizer entity type: $entity" }
    $converted.Value = "summon $entity $x $y $z {Rotation:[${yaw}f,${pitch}f]}"
    return $true
}

function Convert-LegacyBlock([string]$line, [ref]$converted) {
    if ($line -notmatch '^(setblock\s+\S+\s+\S+\s+\S+\s+)chain(\[.*\])\s*$') { return $false }
    $converted.Value = "$($Matches[1])iron_chain$($Matches[2])"
    return $true
}

function Import-BloxelizerZip([string]$zipPath, [string]$requestedName, [string]$destination) {
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or [IO.Path]::GetExtension($zipPath).ToLowerInvariant() -ne '.zip') { throw 'Select an existing ZIP file.' }
    $name = Normalize-StructureName $requestedName
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'Enter a structure name using letters, numbers, underscores, hyphens, or periods.' }
    if ($name -ne $requestedName.Trim().ToLowerInvariant()) {
        if ([Windows.Forms.MessageBox]::Show("The name will be normalized to:`r`n`r`n$name`r`n`r`nContinue?", 'Normalize name', 'YesNo', 'Information') -ne 'Yes') { return $null }
    }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('BloxelizerImporter_' + [guid]::NewGuid().ToString('N'))
    $extractRoot = Join-Path $tempRoot 'extracted'; $stageRoot = Join-Path $tempRoot 'staged'
    try {
        [IO.Directory]::CreateDirectory($extractRoot) | Out-Null; [IO.Directory]::CreateDirectory($stageRoot) | Out-Null
        $rootWithSlash = [IO.Path]::GetFullPath($extractRoot + [IO.Path]::DirectorySeparatorChar)
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrEmpty($entry.Name)) { continue }
                $target = [IO.Path]::GetFullPath((Join-Path $extractRoot $entry.FullName.Replace('/', '\')))
                if (-not $target.StartsWith($rootWithSlash, [StringComparison]::OrdinalIgnoreCase)) { throw 'The ZIP contains an unsafe path.' }
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
        } finally { $archive.Dispose() }

        $all = Get-FunctionFiles $extractRoot
        $source = Get-ExportFiles $all
        if ($all.Count -eq 0) { throw 'The ZIP contains no .mcfunction files.' }
        if ($source.Count -eq 0 -or -not ($source.Name -contains 'creation.mcfunction')) { throw 'The ZIP must contain creation.mcfunction.' }
        if (@($source | Group-Object Name | Where-Object Count -gt 1).Count -gt 0) { throw 'The ZIP contains duplicate function filenames.' }

        $renameMap=@{}; $targets=@()
        foreach ($file in $source) {
            $key=[IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ($key -eq 'creation') { $new=$name } else { $new=$name+'_'+$key.Substring(9) }
            $renameMap[$key]=$new; $targets += "$new.mcfunction"
        }
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        $existing=@($targets | Where-Object { Test-Path -LiteralPath (Join-Path $destination $_) -PathType Leaf })
        if ($existing.Count -gt 0 -and [Windows.Forms.MessageBox]::Show("These files already exist:`r`n`r`n$($existing -join "`r`n")`r`n`r`nOverwrite them?", 'Structure exists', 'YesNo', 'Warning') -ne 'Yes') { return $null }

        $referencePattern='(?<![A-Za-z0-9_.-])'+[regex]::Escape($namespace)+':([A-Za-z0-9_.-]+)(?![A-Za-z0-9_.-])'
        $entities=0; $legacy=0
        foreach ($file in $source) {
            $key=[IO.Path]::GetFileNameWithoutExtension($file.Name); $lines=[IO.File]::ReadAllText($file.FullName) -split "`r?`n",-1
            $processed=foreach($line in $lines){
                $converted=$null
                if(Convert-EntityMarker $line ([ref]$converted)){$entities++;$converted;continue}
                if(Convert-LegacyBlock $line ([ref]$converted)){$legacy++;$converted;continue}
                if($line -match '__entity=1'){throw "Could not convert an entity marker in $($file.Name)."}
                [regex]::Replace($line,$referencePattern,{param($m) $ref=$m.Groups[1].Value; if($renameMap.ContainsKey($ref)){return "${namespace}:$($renameMap[$ref])"};return $m.Value})
            }
            [IO.File]::WriteAllText((Join-Path $stageRoot "$($renameMap[$key]).mcfunction"),($processed -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
        }
        foreach($target in $targets){[IO.File]::Copy((Join-Path $stageRoot $target),(Join-Path $destination $target),$true)}
        [pscustomobject]@{Name=$name;Count=$source.Count;Entities=$entities;Legacy=$legacy}
    } finally { if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue} }
}

$destination = Load-Destination
if ([string]::IsNullOrWhiteSpace($destination)) { return }

$form=New-Object Windows.Forms.Form; $form.Text='Bloxelizer Function Importer'; $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false; $form.ClientSize=New-Object Drawing.Size(600,350)
$title=New-Object Windows.Forms.Label; $title.Text='Bloxelizer Function Importer'; $title.Font=New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold); $title.AutoSize=$true; $title.Location=New-Object Drawing.Point(18,16); $form.Controls.Add($title)
$zipLabel=New-Object Windows.Forms.Label; $zipLabel.Text='Bloxelizer ZIP:'; $zipLabel.AutoSize=$true; $zipLabel.Location=New-Object Drawing.Point(20,68); $form.Controls.Add($zipLabel)
$zipBox=New-Object Windows.Forms.TextBox; $zipBox.Location=New-Object Drawing.Point(20,88); $zipBox.Size=New-Object Drawing.Size(460,24); $form.Controls.Add($zipBox)
$browse=New-Object Windows.Forms.Button; $browse.Text='Browse...'; $browse.Location=New-Object Drawing.Point(490,86); $browse.Size=New-Object Drawing.Size(85,28); $browse.Add_Click({$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='ZIP files (*.zip)|*.zip|All files (*.*)|*.*';if($d.ShowDialog() -eq 'OK'){$zipBox.Text=$d.FileName}});$form.Controls.Add($browse)
$nameLabel=New-Object Windows.Forms.Label;$nameLabel.Text='Structure Name:';$nameLabel.AutoSize=$true;$nameLabel.Location=New-Object Drawing.Point(20,132);$form.Controls.Add($nameLabel)
$nameBox=New-Object Windows.Forms.TextBox;$nameBox.Location=New-Object Drawing.Point(20,152);$nameBox.Size=New-Object Drawing.Size(555,24);$form.Controls.Add($nameBox)
$destLabel=New-Object Windows.Forms.Label;$destLabel.Text="Destination:  $destination";$destLabel.AutoSize=$true;$destLabel.MaximumSize=New-Object Drawing.Size(555,0);$destLabel.Location=New-Object Drawing.Point(20,194);$form.Controls.Add($destLabel)
$status=New-Object Windows.Forms.Label;$status.Text='Select a ZIP and enter the structure name.';$status.ForeColor=[Drawing.Color]::DimGray;$status.AutoSize=$true;$status.Location=New-Object Drawing.Point(20,246);$form.Controls.Add($status)
$import=New-Object Windows.Forms.Button;$import.Text='Import';$import.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold);$import.Location=New-Object Drawing.Point(465,292);$import.Size=New-Object Drawing.Size(110,36);$import.Add_Click({$import.Enabled=$false;$browse.Enabled=$false;try{$r=Import-BloxelizerZip $zipBox.Text $nameBox.Text $destination;if($null -eq $r){return};$status.Text="Import successful! Imported $($r.Count) files.";$status.ForeColor=[Drawing.Color]::DarkGreen;[Windows.Forms.MessageBox]::Show("Import successful!`r`n`r`nImported $($r.Count) function files.`r`nConverted $($r.Entities) entities and $($r.Legacy) legacy block names.`r`n`r`nRun:`r`n/reload`r`n/function ${namespace}:$($r.Name)",'Import successful','OK','Information')|Out-Null}catch{$status.Text='Import failed.';$status.ForeColor=[Drawing.Color]::DarkRed;Show-Error $_.Exception.Message}finally{$import.Enabled=$true;$browse.Enabled=$true}});$form.Controls.Add($import)
$form.AcceptButton=$import;[void]$form.ShowDialog()

