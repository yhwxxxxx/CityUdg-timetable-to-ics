$ErrorActionPreference = "Stop"
$env:TIMETABLE_IMPORTER_NO_GUI = "1"
. (Join-Path $PSScriptRoot "..\timetable_importer.ps1")

$imagePath = Join-Path ([IO.Path]::GetTempPath()) ("timetable_ocr_test_" + [guid]::NewGuid().ToString("N") + ".png")
$bitmap = [Drawing.Bitmap]::new(1200, 700)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$green = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(200, 235, 200))
$black = [Drawing.Brushes]::Black
$font = [Drawing.Font]::new("Arial", 28, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)

try {
    $graphics.Clear([Drawing.Color]::White)
    $graphics.FillRectangle($green, 40, 150, 510, 350)
    $graphics.FillRectangle($green, 650, 150, 510, 350)
    $graphics.DrawString("Monday", $font, $black, 80, 20)
    $graphics.DrawString("Jan 28", $font, $black, 80, 70)
    $graphics.DrawString("Tuesday", $font, $black, 690, 20)
    $graphics.DrawString("Jan 29", $font, $black, 690, 70)
    $graphics.DrawString("Math Lecture", $font, $black, 80, 190)
    $graphics.DrawString("11:00 AM - 1:00 PM", $font, $black, 80, 245)
    $graphics.DrawString("Room: Lab", $font, $black, 80, 300)
    $graphics.DrawString("Physics Lecture", $font, $black, 690, 190)
    $graphics.DrawString("2:00 PM - 4:00 PM", $font, $black, 690, 245)
    $graphics.DrawString("Room: Hall", $font, $black, 690, 300)
    $bitmap.Save($imagePath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $font.Dispose()
    $green.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

try {
    $text = Get-TextFromImage -ImagePath $imagePath -Year 2019
    $result = Convert-ScheduleTextToEvents -Text $text -Year 2019
    if ($result.Events.Count -ne 2) {
        throw "Expected 2 recognized courses, got $($result.Events.Count). OCR text: $text"
    }
    $grid = New-Object System.Windows.Forms.DataGridView
    try {
        foreach ($column in @("Date", "StartTime", "EndTime", "Title", "Location")) { [void]$grid.Columns.Add($column, $column) }
        $course = $result.Events[0]
        [void]$grid.Rows.Add($course.Start.ToString("yyyy-MM-dd"), "12:00", "14:00", "Edited Math", "New Lab")
        $edited = Get-EventsFromGrid -Grid $grid
        if ($edited.Count -ne 1 -or $edited[0].Start.Hour -ne 12 -or $edited[0].Location -ne "New Lab") {
            throw "Recognized course edits were not applied"
        }
        $ics = Convert-EventsToIcs -Events $edited -CalendarName "Test Calendar"
        if (-not $ics.Contains("SUMMARY:Edited Math") -or -not $ics.Contains("LOCATION:New Lab")) {
            throw "Edited course was not exported"
        }
    }
    finally {
        $grid.Dispose()
    }
    Write-Host "OCR integration test passed"
}
finally {
    Remove-Item -LiteralPath $imagePath -Force -ErrorAction SilentlyContinue
}
