$ErrorActionPreference = "Stop"
$env:TIMETABLE_IMPORTER_NO_GUI = "1"
. (Join-Path $PSScriptRoot "..\timetable_importer.ps1")

function Assert-Equal {
    param($Actual, $Expected, [string]$Name)
    if ($Actual -ne $Expected) {
        throw "$Name`: expected [$Expected], got [$Actual]"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "$Name failed" }
}

$date = Get-Date -Year 2026 -Month 9 -Day 25
$sample = Get-SampleScheduleText -Year 2026
$sampleParsed = Convert-ScheduleTextToEvents -Text $sample -Year 2026
Assert-Equal $sampleParsed.Events.Count 3 "current year sample event count"
Assert-Equal $sampleParsed.Warnings.Count 0 "current year sample dates"
$range = Parse-TimeRange -Line "11:00 - 1:00 PM" -Date $date
Assert-Equal $range.Start.Hour 11 "end period infers morning start"
Assert-Equal $range.End.Hour 13 "end period gives afternoon end"
$range = Parse-TimeRange -Line "2:00 PM - 4:50" -Date $date
Assert-Equal $range.Start.Hour 14 "start period gives afternoon start"
Assert-Equal $range.End.Hour 16 "start period infers afternoon end"
$range = Parse-TimeRange -Line "11:00 PM - 1:00" -Date $date
Assert-Equal $range.End.Day 26 "overnight end day"
Assert-Equal $range.End.Hour 1 "overnight end hour"

$ocrRange = Convert-OcrTimeRangeText "11:00-1:00 PM"
$range = Parse-TimeRange -Line $ocrRange -Date $date
Assert-Equal $range.Start.Hour 11 "OCR keeps missing start period"
Assert-Equal $range.End.Hour 13 "OCR end period"

$text = "Monday, Jan 28`nCourse A`n9:00 AM - 10:00 AM`nRoom:`nCourse B`n11:00 AM - 12:00 PM`nRoom: Lab"
$parsed = Convert-ScheduleTextToEvents -Text $text -Year 2019
Assert-Equal $parsed.Events.Count 2 "empty room followed by another course"
Assert-Equal $parsed.Events[0].Location "" "empty room value"
Assert-Equal $parsed.Events[1].Location "Lab" "next course location"
Assert-Equal $parsed.Warnings.Count 0 "valid empty room has no warning"

$text = "Monday, Jan 28`nCourse A`n9:00 AM - 10:00 AM"
$parsed = Convert-ScheduleTextToEvents -Text $text -Year 2019
Assert-Equal $parsed.Events.Count 1 "final course without room"
Assert-Equal $parsed.Events[0].Location "" "missing final room"

$text = "Monday, Feb 30`nBad Course`n9:00 AM - 10:00 AM`nRoom: A`nWednesday, Mar 4`nGood Course`n9:00 AM - 10:00 AM`nRoom: B"
$parsed = Convert-ScheduleTextToEvents -Text $text -Year 2026
Assert-Equal $parsed.Events.Count 1 "invalid date does not corrupt later date"
Assert-Equal $parsed.Events[0].Title "Good Course" "later course survives invalid date"
Assert-True ($parsed.Warnings.Count -gt 0) "invalid date reports warning"

$confirmed = Convert-ScheduleTextToEvents -Text "Monday, Jan 28`nCourse A`n9:00 AM - 10:00 AM`nRoom: A" -Year 2019
$copy = Copy-EventsForEditing -Events $confirmed.Events
Assert-Equal $copy.Count 1 "single course stays a collection in editor"
$confirmedText = Convert-EventsToScheduleText -Events $confirmed.Events
$sameYear = Get-ExportResult -Text $confirmedText -Year 2019 -ConfirmedEvents $confirmed.Events -ConfirmedText $confirmedText -ConfirmedYear 2019
Assert-Equal $sameYear.Events[0].Start.Year 2019 "confirmed year reused"
$newYear = Get-ExportResult -Text $confirmedText -Year 2020 -ConfirmedEvents $confirmed.Events -ConfirmedText $confirmedText -ConfirmedYear 2019
Assert-Equal $newYear.Events[0].Start.Year 2020 "changed year reparsed"

$grid = New-Object System.Windows.Forms.DataGridView
foreach ($column in @("Date", "StartTime", "EndTime", "Title", "Location")) { [void]$grid.Columns.Add($column, $column) }
[void]$grid.Rows.Add("2026-09-25", "11:00", "13:00", "Edited Course", "Room A")
$edited = Get-EventsFromGrid -Grid $grid
Assert-Equal $edited.Count 1 "grid edit returns course"
Assert-Equal $edited[0].Start.Hour 11 "grid edit start time"
Assert-Equal $edited[0].End.Hour 13 "grid edit end time"
$grid.Rows[0].Cells["Date"].Value = "2026-02-30"
$invalidGridDate = $false
try { [void](Get-EventsFromGrid -Grid $grid) } catch { $invalidGridDate = $true }
Assert-True $invalidGridDate "grid edit rejects impossible date"
$grid.Dispose()

$secondWeekEvent = [pscustomobject]@{
    Title = "Second Week"
    Start = $confirmed.Events[0].Start.AddDays(7)
    End = $confirmed.Events[0].End.AddDays(7)
    Location = "Room B"
    SourceDate = "Monday, Feb 4"
}
$weekTable = New-Object System.Windows.Forms.TableLayoutPanel
Update-WeekTablePreview -WeekTable $weekTable -Events @($confirmed.Events[0], $secondWeekEvent)
Assert-Equal $weekTable.RowCount 4 "week preview includes two weeks"
Assert-Equal $weekTable.Controls.Count 28 "week preview contains both week grids"
$weekTable.Dispose()

function New-OcrLine {
    param([string]$Text, [double]$X, [double]$Y)
    return [pscustomobject]@{ Text = $Text; Left = $X - 40; Right = $X + 40; Top = $Y - 8; Bottom = $Y + 8; CenterX = $X; CenterY = $Y }
}
$analysis = [pscustomobject]@{
    Width = 600
    Height = 600
    Lines = @(
        (New-OcrLine "Monday" 100 20), (New-OcrLine "Jan 28" 100 45),
        (New-OcrLine "Tuesday" 400 20), (New-OcrLine "Jan 29" 400 45),
        (New-OcrLine "Course A" 100 120), (New-OcrLine "11:00 - 1:00 PM" 100 150), (New-OcrLine "Room: Lab" 100 180),
        (New-OcrLine "Course B" 400 120), (New-OcrLine "2:00 PM - 4:00 PM" 400 150), (New-OcrLine "Room: Hall" 400 180)
    )
    Blocks = @(
        [pscustomobject]@{ Left = 20; Right = 180; Top = 100; Bottom = 210 },
        [pscustomobject]@{ Left = 320; Right = 480; Top = 100; Bottom = 210 }
    )
}
$gridText = Convert-OcrGridToScheduleText -Analysis $analysis -Year 2019
$parsedGrid = Convert-ScheduleTextToEvents -Text $gridText -Year 2019
Assert-Equal $parsedGrid.Events.Count 2 "OCR grid maps both day columns"
Assert-Equal $parsedGrid.Events[0].Start.Hour 11 "OCR grid time inference"

$longTitle = ("中文课程" * 12) + ", Advanced; Study"
$icsEvent = [pscustomobject]@{ Title = $longTitle; Start = $date; End = $date.AddHours(1); Location = "教室, A"; SourceDate = "Friday, Sep 25" }
$ics = Convert-EventsToIcs -Events @($icsEvent) -CalendarName "课程表"
foreach ($line in ($ics -split "`r`n" | Where-Object { $_ -ne "" })) {
    Assert-True ([Text.Encoding]::UTF8.GetByteCount($line) -le 75) "ICS physical line stays within 75 UTF-8 bytes"
}
$unfolded = $ics -replace "`r`n ", ""
Assert-True ($unfolded.Contains("SUMMARY:$($longTitle.Replace(',', '\,').Replace(';', '\;'))")) "ICS title survives folding"

Write-Host "All logic tests passed"
