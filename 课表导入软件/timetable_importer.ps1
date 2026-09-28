Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-SampleScheduleText {
    param([int]$Year)

    $monday = [datetime]::new($Year, 1, 1)
    while ($monday.DayOfWeek -ne [DayOfWeek]::Monday) {
        $monday = $monday.AddDays(1)
    }
    $tuesday = $monday.AddDays(1)
    $culture = [Globalization.CultureInfo]::GetCultureInfo("en-US")
    return @"
Monday, $($monday.ToString('MMM d', $culture))
GE 2410 Lecture
2:00 PM - 4:50 PM
Room: Classroom, AC3-214
Tuesday, $($tuesday.ToString('MMM d', $culture))
MA 1301 Lecture
8:30 AM - 10:20 AM
Room: Lecture Theater, ACS-316
MA 1301 Lecture
2:00 PM - 2:50 PM
Room: Lecture Theater, ACS-316
"@
}

$script:CurrentEvents = $null
$script:CurrentEventsText = ""
$script:CurrentEventsYear = $null
$script:CityURed = [System.Drawing.Color]::FromArgb(143, 20, 45)
$script:CityUDarkBlue = [System.Drawing.Color]::FromArgb(31, 54, 92)
$script:CityULightRed = [System.Drawing.Color]::FromArgb(248, 235, 239)
$script:CityULightBlue = [System.Drawing.Color]::FromArgb(235, 240, 247)
$script:CityUText = [System.Drawing.Color]::FromArgb(35, 35, 35)

function Escape-IcsText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    return $Text.Replace("\", "\\").Replace(";", "\;").Replace(",", "\,").Replace("`r`n", "\n").Replace("`n", "\n")
}

function Fold-IcsLine {
    param([string]$Line)

    $maxBytes = 75
    $parts = New-Object System.Collections.Generic.List[string]
    $part = New-Object System.Text.StringBuilder
    $byteCount = 0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $character = [string]$Line[$i]
        if ([char]::IsHighSurrogate($Line[$i]) -and $i + 1 -lt $Line.Length -and [char]::IsLowSurrogate($Line[$i + 1])) {
            $i++
            $character += [string]$Line[$i]
        }
        $characterBytes = [Text.Encoding]::UTF8.GetByteCount($character)
        if ($byteCount + $characterBytes -gt $maxBytes) {
            $parts.Add($part.ToString())
            [void]$part.Clear()
            [void]$part.Append(" ")
            $byteCount = 1
        }
        [void]$part.Append($character)
        $byteCount += $characterBytes
    }
    $parts.Add($part.ToString())
    return ($parts -join "`r`n")
}

function ConvertTo-IcsDateTime {
    param([datetime]$Value)

    return $Value.ToString("yyyyMMdd'T'HHmmss", [Globalization.CultureInfo]::InvariantCulture)
}

function Convert-WeekdayToEnglish {
    param([string]$Weekday)

    if ([string]::IsNullOrWhiteSpace($Weekday)) { return "" }

    $value = $Weekday.Trim().ToLowerInvariant()
    $map = @{
        "monday" = "Monday"; "mon" = "Monday"; "星期一" = "Monday"; "周一" = "Monday"; "週一" = "Monday"; "礼拜一" = "Monday"; "禮拜一" = "Monday"
        "tuesday" = "Tuesday"; "tue" = "Tuesday"; "星期二" = "Tuesday"; "周二" = "Tuesday"; "週二" = "Tuesday"; "礼拜二" = "Tuesday"; "禮拜二" = "Tuesday"
        "wednesday" = "Wednesday"; "wed" = "Wednesday"; "星期三" = "Wednesday"; "周三" = "Wednesday"; "週三" = "Wednesday"; "礼拜三" = "Wednesday"; "禮拜三" = "Wednesday"
        "thursday" = "Thursday"; "thu" = "Thursday"; "星期四" = "Thursday"; "周四" = "Thursday"; "週四" = "Thursday"; "礼拜四" = "Thursday"; "禮拜四" = "Thursday"
        "friday" = "Friday"; "fri" = "Friday"; "星期五" = "Friday"; "周五" = "Friday"; "週五" = "Friday"; "礼拜五" = "Friday"; "禮拜五" = "Friday"
        "saturday" = "Saturday"; "sat" = "Saturday"; "星期六" = "Saturday"; "周六" = "Saturday"; "週六" = "Saturday"; "礼拜六" = "Saturday"; "禮拜六" = "Saturday"
        "sunday" = "Sunday"; "sun" = "Sunday"; "星期日" = "Sunday"; "星期天" = "Sunday"; "周日" = "Sunday"; "周天" = "Sunday"; "週日" = "Sunday"; "週天" = "Sunday"; "礼拜日" = "Sunday"; "礼拜天" = "Sunday"; "禮拜日" = "Sunday"; "禮拜天" = "Sunday"
    }

    if ($map.ContainsKey($value)) { return $map[$value] }
    return $Weekday
}

function Convert-DateLineToScheduleHeader {
    param(
        [datetime]$Date,
        [string]$Weekday = ""
    )

    $dayName = if ($Weekday -ne "") { Convert-WeekdayToEnglish $Weekday } else { $Date.ToString("dddd", [Globalization.CultureInfo]::GetCultureInfo("en-US")) }
    return "$dayName, $($Date.ToString('MMM d', [Globalization.CultureInfo]::GetCultureInfo('en-US')))"
}

function Parse-ScheduleDateLine {
    param(
        [string]$Line,
        [int]$Year
    )

    $monthMap = @{
        Jan = 1; January = 1
        Feb = 2; February = 2
        Mar = 3; March = 3
        Apr = 4; April = 4
        May = 5
        Jun = 6; June = 6
        Jul = 7; July = 7
        Aug = 8; August = 8
        Sep = 9; Sept = 9; September = 9
        Oct = 10; October = 10
        Nov = 11; November = 11
        Dec = 12; December = 12
    }

    $trimmed = $Line.Trim()
    $weekdayPattern = '(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun|星期一|星期二|星期三|星期四|星期五|星期六|星期日|星期天|周一|周二|周三|周四|周五|周六|周日|周天|週一|週二|週三|週四|週五|週六|週日|週天|礼拜一|礼拜二|礼拜三|礼拜四|礼拜五|礼拜六|礼拜日|礼拜天|禮拜一|禮拜二|禮拜三|禮拜四|禮拜五|禮拜六|禮拜日|禮拜天)'
    $englishPattern = "^(?<weekday>$weekdayPattern)?[,]?\s*(?<month>[A-Za-z]+)\s+(?<day>\d{1,2})$"
    $englishMatch = [regex]::Match($trimmed, $englishPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($englishMatch.Success) {
        $monthName = $englishMatch.Groups["month"].Value
        $monthKey = $monthMap.Keys | Where-Object { $_.ToLowerInvariant() -eq $monthName.ToLowerInvariant() } | Select-Object -First 1
        if ($null -ne $monthKey) {
            $date = [datetime]::new($Year, [int]$monthMap[$monthKey], [int]$englishMatch.Groups["day"].Value)
            return [pscustomobject]@{
                Success = $true
                Date = $date
                Weekday = Convert-WeekdayToEnglish $englishMatch.Groups["weekday"].Value
                Label = $trimmed
            }
        }
    }

    $chinesePattern = "^(?<weekday>$weekdayPattern)?[,]?\s*(?<month>\d{1,2})\s*[月/-]\s*(?<day>\d{1,2})\s*(日|号|號)?$"
    $chineseMatch = [regex]::Match($trimmed, $chinesePattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($chineseMatch.Success) {
        $date = [datetime]::new($Year, [int]$chineseMatch.Groups["month"].Value, [int]$chineseMatch.Groups["day"].Value)
        return [pscustomobject]@{
            Success = $true
            Date = $date
            Weekday = Convert-WeekdayToEnglish $chineseMatch.Groups["weekday"].Value
            Label = $trimmed
        }
    }

    return [pscustomobject]@{
        Success = $false
        Date = $null
        Weekday = ""
        Label = $trimmed
    }
}

function Parse-TimeValue {
    param(
        [string]$Text,
        [datetime]$Date,
        [string]$FallbackPeriod = ""
    )

    $value = $Text.Trim()
    $period = ""
    if ($value -match '(?i)(AM|PM)') { $period = $Matches[1].ToUpperInvariant() }
    elseif ($value -match '(上午|早上)') { $period = "AM" }
    elseif ($value -match '(下午|晚上|晚間|晚间)') { $period = "PM" }
    elseif ($value -match '(中午)') { $period = "NOON" }
    elseif ($FallbackPeriod -ne "") { $period = $FallbackPeriod }

    $clean = $value -replace '(?i)(AM|PM)', ''
    $clean = $clean -replace '(上午|早上|下午|晚上|晚間|晚间|中午)', ''
    $clean = $clean.Trim()

    $match = [regex]::Match($clean, '^(?<hour>\d{1,2})(:(?<minute>\d{2}))?$')
    if (-not $match.Success) { return $null }

    $hour = [int]$match.Groups["hour"].Value
    $minute = if ($match.Groups["minute"].Success) { [int]$match.Groups["minute"].Value } else { 0 }
    if ($minute -lt 0 -or $minute -gt 59) { return $null }

    if ($period -eq "AM") {
        if ($hour -eq 12) { $hour = 0 }
    }
    elseif ($period -eq "PM") {
        if ($hour -lt 12) { $hour += 12 }
    }
    elseif ($period -eq "NOON") {
        if ($hour -lt 12) { $hour += 12 }
    }

    if ($hour -lt 0 -or $hour -gt 23) { return $null }
    return $Date.Date.AddHours($hour).AddMinutes($minute)
}

function Parse-TimeRange {
    param(
        [string]$Line,
        [datetime]$Date
    )

    $lineText = $Line.Trim().Replace("－", "-").Replace("–", "-").Replace("—", "-").Replace("到", "-").Replace("至", "-")
    $pattern = '^(?<start>(上午|早上|下午|晚上|晚間|晚间|中午)?\s*\d{1,2}(:\d{2})?\s*([AP]M)?)\s*-\s*(?<end>(上午|早上|下午|晚上|晚間|晚间|中午)?\s*\d{1,2}(:\d{2})?\s*([AP]M)?)$'
    $match = [regex]::Match($lineText, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }

    $startText = $match.Groups["start"].Value
    $endText = $match.Groups["end"].Value
    $startHasPeriod = $startText -match '(?i)(AM|PM|上午|早上|下午|晚上|晚間|晚间|中午)'
    $endHasPeriod = $endText -match '(?i)(AM|PM|上午|早上|下午|晚上|晚間|晚间|中午)'

    $startPeriods = if ($startHasPeriod -or -not $endHasPeriod) { @('') } else { @('AM', 'PM') }
    $endPeriods = if ($endHasPeriod -or -not $startHasPeriod) { @('') } else { @('AM', 'PM') }
    $bestRange = $null
    foreach ($startPeriod in $startPeriods) {
        foreach ($endPeriod in $endPeriods) {
            $startDateTime = Parse-TimeValue -Text $startText -Date $Date -FallbackPeriod $startPeriod
            $endDateTime = Parse-TimeValue -Text $endText -Date $Date -FallbackPeriod $endPeriod
            if ($null -eq $startDateTime -or $null -eq $endDateTime) { continue }
            if ($endDateTime -le $startDateTime) { $endDateTime = $endDateTime.AddDays(1) }
            $duration = $endDateTime - $startDateTime
            if ($null -eq $bestRange -or $duration -lt $bestRange.Duration) {
                $bestRange = @{ Start = $startDateTime; End = $endDateTime; Duration = $duration }
            }
        }
    }
    if ($null -eq $bestRange) { return $null }

    return @{
        Start = $bestRange.Start
        End = $bestRange.End
    }
}

function Convert-ScheduleTextToEvents {
    param(
        [string]$Text,
        [int]$Year
    )
    $lines = $Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    $events = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $currentDate = $null
    $currentDateLabel = ""
    $i = 0

    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        try {
            $dateInfo = Parse-ScheduleDateLine -Line $line -Year $Year
        }
        catch {
            $warnings.Add("无法识别日期，已跳过：$line")
            $currentDate = $null
            $i++
            continue
        }

        if ($dateInfo.Success) {
            try {
                $currentDate = $dateInfo.Date
                $currentDateLabel = $line

                $expectedWeekday = $dateInfo.Weekday
                $actualWeekday = $currentDate.ToString("dddd", [Globalization.CultureInfo]::GetCultureInfo("en-US"))
                if ($expectedWeekday -and ($expectedWeekday.ToLowerInvariant() -ne $actualWeekday.ToLowerInvariant())) {
                    $warnings.Add("$line 的星期和 $Year 年实际日期不一致，已按日期导出。")
                }
            }
            catch {
                $warnings.Add("无法生成日期：$line")
                $currentDate = $null
            }

            $i++
            continue
        }

        if ($null -eq $currentDate) {
            $warnings.Add("跳过没有日期归属的内容：$line")
            $i++
            continue
        }

        if ($i + 1 -ge $lines.Count) {
            $warnings.Add("内容不完整，已跳过：$line")
            break
        }

        $title = $line
        $timeLine = $lines[$i + 1]
        $roomLine = if ($i + 2 -lt $lines.Count) { $lines[$i + 2] } else { "" }
        $timeRange = Parse-TimeRange -Line $timeLine -Date $currentDate

        if ($null -eq $timeRange) {
            $warnings.Add("无法识别时间，已跳过：$title / $timeLine")
            $i++
            continue
        }

        if ($roomLine -notmatch '^(Room|教室|课室|課室|地点|地點)\s*[:：]\s*(?<room>.*)$') {
            $warnings.Add("没有找到教室行，已用空地点导出：$title")
            $location = ""
            $i += 2
        }
        else {
            $location = $Matches["room"].Trim()
            $i += 3
        }

        $events.Add([pscustomobject]@{
            Title = $title
            Start = $timeRange.Start
            End = $timeRange.End
            Location = $location
            SourceDate = $currentDateLabel
        })
    }

    return [pscustomobject]@{
        Events = $events
        Warnings = $warnings
    }
}

function Convert-EventsToIcs {
    param(
        [System.Collections.IEnumerable]$Events,
        [string]$CalendarName
    )

    $now = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture)
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("BEGIN:VCALENDAR")
    $lines.Add("VERSION:2.0")
    $lines.Add("PRODID:-//Local Timetable Importer//CN")
    $lines.Add("CALSCALE:GREGORIAN")
    $lines.Add("METHOD:PUBLISH")
    $lines.Add("X-WR-CALNAME:$(Escape-IcsText $CalendarName)")

    foreach ($event in $Events) {
        $uidText = "$($event.Title)-$($event.Start.ToString('yyyyMMddHHmmss'))-$([guid]::NewGuid().ToString('N'))@local-timetable-importer"
        $description = "Imported from: $($event.SourceDate)"

        $lines.Add("BEGIN:VEVENT")
        $lines.Add("UID:$(Escape-IcsText $uidText)")
        $lines.Add("DTSTAMP:$now")
        $lines.Add("DTSTART:$(ConvertTo-IcsDateTime $event.Start)")
        $lines.Add("DTEND:$(ConvertTo-IcsDateTime $event.End)")
        $lines.Add("SUMMARY:$(Escape-IcsText $event.Title)")
        $lines.Add("LOCATION:$(Escape-IcsText $event.Location)")
        $lines.Add("DESCRIPTION:$(Escape-IcsText $description)")
        $lines.Add("END:VEVENT")
    }

    $lines.Add("END:VCALENDAR")
    return (($lines | ForEach-Object { Fold-IcsLine $_ }) -join "`r`n") + "`r`n"
}

function Repair-OcrScheduleText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    $fixed = $Text.Replace("：", ":").Replace("－", "-").Replace("–", "-").Replace("—", "-")
    $fixed = $fixed.Replace("．", ".").Replace("。", ".")
    $fixed = [regex]::Replace($fixed, '(?i)(?<hour>\b\d{1,2})\s*[:]\s*(?<minute>\d{2}\s*[AP]M\b)', '${hour}:${minute}')
    $fixed = [regex]::Replace($fixed, '(?i)(?<hour>\b\d{1,2})\s*[．.]\s*(?<minute>\d{2}\s*[AP]M\b)', '${hour}:${minute}')
    $fixed = [regex]::Replace($fixed, '(?i)\b([AP])\s+M\b', '$1M')
    $fixed = [regex]::Replace($fixed, '\s+-\s+', ' - ')
    $fixed = [regex]::Replace($fixed, '(?m)^\s+|\s+$', '')

    return $fixed
}

function Repair-OcrCourseText {
    param([string]$Text)

    if ($null -eq $Text) { return "" }

    $fixed = $Text.Trim()
    $fixed = $fixed.Replace("_", "")
    $fixed = $fixed.Replace("．", "-").Replace(".", "-")
    $fixed = $fixed.Replace("「", "r").Replace("訂", "r").Replace("旧", "IP")
    $fixed = $fixed.Replace("•", ":").Replace("·", "-")
    $fixed = [regex]::Replace($fixed, '(?i)\bL\s*ecture\b', 'Lecture')
    $fixed = [regex]::Replace($fixed, '(?i)\bL\s*巴\s*C\s*加\b', 'Lecture')
    $fixed = [regex]::Replace($fixed, '(?i)\bL\s*b\s*0\b', 'Laboratory')
    $fixed = [regex]::Replace($fixed, '(?i)\bS\s*-\s*eminar\b', 'Seminar')
    $fixed = [regex]::Replace($fixed, '(?i)Lectu\s*r\s*e', 'Lecture')
    $fixed = [regex]::Replace($fixed, '(?i)\bRO\s+OutdOOr\s+SportS\b', 'Room: Outdoor Sports')
    $fixed = [regex]::Replace($fixed, '(?i)\bRO\s+11\s*[:：]?\s*Classroom\b', 'Room: Classroom')
    $fixed = [regex]::Replace($fixed, '(?i)\bRO\s+创\s+Lecture\s+Hall\b', 'Room: Lecture Hall')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom\s+C\s*[IlS]?\s*r\s*00m\b', 'Room: Classroom')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom\s+CI\s*r\s*00m\b', 'Room: Classroom')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom[\.:]\s*Classroom\b', 'Room: Classroom')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom\s*-\s*Classroom\b', 'Room: Classroom')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom[\.:]\s*Computer\s+Lab\b', 'Room: Computer Lab')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom\s*-\s*Computer\s+Lab\b', 'Room: Computer Lab')
    $fixed = [regex]::Replace($fixed, '(?i)\bRoom\s+Lecture\s+Theater\b', 'Room: Lecture Theater')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC\s*孓\s*', 'AC3-')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC\s*\$\s*', 'ACS-')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC5\b', 'ACS')
    $fixed = [regex]::Replace($fixed, '(?i)\bACI\b', 'AC1')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC\s+213\b', 'AC3-213')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC\s+214\b', 'AC3-214')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC1\s*-\s*201\b', 'AC1-201')
    $fixed = [regex]::Replace($fixed, '(?i)\bAC3-316\b', 'ACS-316')
    $fixed = [regex]::Replace($fixed, '(?i)\bL\s*IP\s*-\s*101\b', 'LIB-101')
    $fixed = [regex]::Replace($fixed, '(?i)\bOSYI\b', 'OSY1')
    $fixed = [regex]::Replace($fixed, '(?i)\bIP\s*1931\b', 'IP 1901')
    $fixed = [regex]::Replace($fixed, '(?i)\bMA\s+1\s+1\b', 'MA 1301')
    $fixed = [regex]::Replace($fixed, '\s+', ' ').Trim()

    return $fixed
}

function Convert-OcrTimeRangeText {
    param([string]$Text)

    if ($null -eq $Text) { return $null }

    $base = $Text.ToUpperInvariant()
    $base = $base.Replace("：", ":").Replace("－", "-").Replace("–", "-").Replace("—", "-")
    $base = $base.Replace("．", "-").Replace(".", "-").Replace("刘", "-")
    $base = $base.Replace("就", "9").Replace("毛", "0").Replace("II", "11")
    $base = [regex]::Replace($base, '(上午|早上)\s*(\d{1,2}(:\d{2})?)', '$2 AM')
    $base = [regex]::Replace($base, '(下午|晚上|晚間|晚间)\s*(\d{1,2}(:\d{2})?)', '$2 PM')
    $base = [regex]::Replace($base, '(中午)\s*(\d{1,2}(:\d{2})?)', '$2 PM')
    $base = [regex]::Replace($base, '[^\x00-\x7F]+', ' ')
    $base = [regex]::Replace($base, '(?i)(S|SO|S0)(?=\s*(AM|PM|$))', '50')
    $base = [regex]::Replace($base, '(?i)(?<=[0-9])O(?=[0-9]|\s*(AM|PM))', '0')
    $base = [regex]::Replace($base, '(?i)(?<=[0-9])G(?=[0-9]|\s*(AM|PM))', '9')
    $base = [regex]::Replace($base, '(?i)&\s*30\s*AM', '8:30 AM')
    $base = [regex]::Replace($base, '(?i)&\s*30\s*PM', '6:30 PM')
    $base = [regex]::Replace($base, '(?i)&\s*AM', '8:30 AM')
    $base = [regex]::Replace($base, '(?i)&\s*PM', '6:30 PM')
    $base = [regex]::Replace($base, '(?i)\b2\s*:\s*PM\s*[-\s:]+50\s*PM\b', '2:00 PM-4:50 PM')
    $base = [regex]::Replace($base, '(?i)\b6\s*:\s*PM\s*[-]\s*9', '6:30 PM-9')
    $base = [regex]::Replace($base, '(?i)\b([AP])\s*M\b', '$1M')
    $base = [regex]::Replace($base, '(?i)\b(\d{1,2})\s*[-:]\s*([0-5][0-9])\s*(?=[AP]M\b)', '$1:$2')
    $base = [regex]::Replace($base, '(?i)\b(\d{1,2})\s*[-:]\s*(?=[AP]M\b)', '$1:00')
    $base = [regex]::Replace($base, '\s+', ' ').Trim()

    $variants = @(
        $base,
        $base.Replace("-", ":"),
        $base.Replace(" ", "")
    ) | Select-Object -Unique

    foreach ($variant in $variants) {
        $value = $variant
        $value = [regex]::Replace($value, '(?i)\b(\d{1,2})([0-5][0-9])\s*(?=[AP]M\b)', '$1:$2')
        $value = [regex]::Replace($value, '(?i)\b(\d{1,2})\s+([0-5][0-9])\s*(?=[AP]M\b|-)', '$1:$2')
        $value = [regex]::Replace($value, '(?i)\b(\d{1,2})\s*:\s*(?=[AP]M\b)', '$1:00')
        $value = [regex]::Replace($value, '(?i)\b(\d{1,2})\s+(?=[AP]M\b)', '$1:00 ')

        $rangePattern = '(?i)\b(?<h1>\d{1,2})(?::(?<m1>[0-5][0-9]))?\s*(?<p1>[AP]M)?\s*[-]\s*(?<h2>\d{1,2})(?::(?<m2>[0-5][0-9]))?\s*(?<p2>[AP]M)?\b'
        $rangeMatch = [regex]::Match($value, $rangePattern)
        if ($rangeMatch.Success) {
            $h1 = [int]$rangeMatch.Groups["h1"].Value
            $h2 = [int]$rangeMatch.Groups["h2"].Value
            if ($h1 -lt 0 -or $h1 -gt 23 -or $h2 -lt 0 -or $h2 -gt 23) { continue }

            $m1 = if ($rangeMatch.Groups["m1"].Success) { $rangeMatch.Groups["m1"].Value } else { "00" }
            $m2 = if ($rangeMatch.Groups["m2"].Success) { $rangeMatch.Groups["m2"].Value } else { "00" }
            $p1 = if ($rangeMatch.Groups["p1"].Success) { $rangeMatch.Groups["p1"].Value } else { "" }
            $p2 = if ($rangeMatch.Groups["p2"].Success) { $rangeMatch.Groups["p2"].Value } else { "" }

            if ($p1 -eq "" -and $p2 -eq "") {
                if ($h1 -le 23 -and $h2 -le 23) {
                    return ("{0}:{1} - {2}:{3}" -f $h1, $m1, $h2, $m2)
                }
                continue
            }

            if ($h1 -lt 1 -or $h1 -gt 12 -or $h2 -lt 1 -or $h2 -gt 12) { continue }

            return ("{0}:{1} {2} - {3}:{4} {5}" -f $h1, $m1, $p1, $h2, $m2, $p2).Replace("  ", " ").Trim()
        }

        $tokenPattern = '(?i)\b(?<h>\d{1,2})(?::(?<m>[0-5][0-9]))?\s*(?<p>[AP]M)\b'
        $matches = [regex]::Matches($value, $tokenPattern)
        if ($matches.Count -ge 2) {
            $first = $matches[0]
            $last = $matches[$matches.Count - 1]
            $h1 = [int]$first.Groups["h"].Value
            $h2 = [int]$last.Groups["h"].Value
            if ($h1 -lt 1 -or $h1 -gt 12 -or $h2 -lt 1 -or $h2 -gt 12) { continue }

            $m1 = if ($first.Groups["m"].Success) { $first.Groups["m"].Value } else { "00" }
            $m2 = if ($last.Groups["m"].Success) { $last.Groups["m"].Value } else { "00" }
            return ("{0}:{1} {2} - {3}:{4} {5}" -f $h1, $m1, $first.Groups["p"].Value, $h2, $m2, $last.Groups["p"].Value)
        }
    }

    return $null
}

function Ensure-ScheduleImageAnalyzer {
    if ("ScheduleImageAnalyzer" -as [type]) { return }

    $source = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class CourseBlock {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
    public int Area;
}

public static class ScheduleImageAnalyzer {
    private static bool IsCourseGreen(byte r, byte g, byte b) {
        return g >= 175 && r >= 145 && b >= 145 && g - r >= 8 && g - b >= 5;
    }

    public static CourseBlock[] FindGreenBlocks(string path) {
        using (Bitmap source = new Bitmap(path))
        using (Bitmap bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb)) {
            using (Graphics graphics = Graphics.FromImage(bitmap)) {
                graphics.DrawImage(source, 0, 0, source.Width, source.Height);
            }

            int width = bitmap.Width;
            int height = bitmap.Height;
            int total = width * height;
            byte[] mask = new byte[total];
            byte[] visited = new byte[total];
            int[] queue = new int[total];

            BitmapData data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try {
                int bytesLength = Math.Abs(data.Stride) * height;
                byte[] bytes = new byte[bytesLength];
                Marshal.Copy(data.Scan0, bytes, 0, bytesLength);

                for (int y = 0; y < height; y++) {
                    int rowOffset = y * data.Stride;
                    for (int x = 0; x < width; x++) {
                        int byteIndex = rowOffset + x * 4;
                        byte b = bytes[byteIndex];
                        byte g = bytes[byteIndex + 1];
                        byte r = bytes[byteIndex + 2];
                        if (IsCourseGreen(r, g, b)) {
                            mask[y * width + x] = 1;
                        }
                    }
                }
            }
            finally {
                bitmap.UnlockBits(data);
            }

            List<CourseBlock> blocks = new List<CourseBlock>();
            int minArea = Math.Max(800, total / 3000);
            int minWidth = Math.Max(35, width / 60);
            int minHeight = Math.Max(18, height / 45);

            for (int start = 0; start < total; start++) {
                if (mask[start] == 0 || visited[start] != 0) { continue; }

                int head = 0;
                int tail = 0;
                queue[tail++] = start;
                visited[start] = 1;

                int minX = width;
                int minY = height;
                int maxX = 0;
                int maxY = 0;
                int area = 0;

                while (head < tail) {
                    int index = queue[head++];
                    int x = index % width;
                    int y = index / width;
                    area++;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;

                    int next;
                    if (x > 0) {
                        next = index - 1;
                        if (mask[next] != 0 && visited[next] == 0) { visited[next] = 1; queue[tail++] = next; }
                    }
                    if (x + 1 < width) {
                        next = index + 1;
                        if (mask[next] != 0 && visited[next] == 0) { visited[next] = 1; queue[tail++] = next; }
                    }
                    if (y > 0) {
                        next = index - width;
                        if (mask[next] != 0 && visited[next] == 0) { visited[next] = 1; queue[tail++] = next; }
                    }
                    if (y + 1 < height) {
                        next = index + width;
                        if (mask[next] != 0 && visited[next] == 0) { visited[next] = 1; queue[tail++] = next; }
                    }
                }

                int blockWidth = maxX - minX + 1;
                int blockHeight = maxY - minY + 1;
                if (area >= minArea && blockWidth >= minWidth && blockHeight >= minHeight) {
                    blocks.Add(new CourseBlock { Left = minX, Top = minY, Right = maxX, Bottom = maxY, Area = area });
                }
            }

            return blocks.ToArray();
        }
    }
}
"@

    Add-Type -TypeDefinition $source -ReferencedAssemblies "System.Drawing"
}

function Await-WinRtOperation {
    param(
        [object]$Operation,
        [Type]$ResultType
    )

    $asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq "AsTask" -and
            $_.IsGenericMethod -and
            $_.GetGenericArguments().Count -eq 1 -and
            $_.GetParameters().Count -eq 1 -and
            $_.ToString().Contains("IAsyncOperation")
        } |
        Select-Object -First 1

    if ($null -eq $asTaskMethod) {
        throw "这台电脑无法调用 Windows 图片文字识别组件。"
    }

    $task = $asTaskMethod.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

function Get-OcrReadyImagePath {
    param([string]$ImagePath)

    $maxDimension = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    $image = [System.Drawing.Image]::FromFile($ImagePath)

    try {
        $largestSide = [Math]::Max($image.Width, $image.Height)
        $targetLargestSide = 3200
        $scale = 1.0

        if ($largestSide -gt $maxDimension) {
            $scale = $maxDimension / $largestSide
        }
        elseif ($largestSide -lt $targetLargestSide) {
            $scale = [Math]::Min(2.0, [Math]::Min($targetLargestSide / $largestSide, $maxDimension / $largestSide))
        }

        if ([Math]::Abs($scale - 1.0) -lt 0.05) {
            return [pscustomobject]@{
                Path = $ImagePath
                IsTemporary = $false
            }
        }

        $newWidth = [Math]::Max(1, [int][Math]::Floor($image.Width * $scale))
        $newHeight = [Math]::Max(1, [int][Math]::Floor($image.Height * $scale))
        $resized = New-Object System.Drawing.Bitmap $newWidth, $newHeight
        $graphics = [System.Drawing.Graphics]::FromImage($resized)

        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.DrawImage($image, 0, 0, $newWidth, $newHeight)

            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("timetable_ocr_" + [guid]::NewGuid().ToString("N") + ".png")
            $resized.Save($tempPath, [System.Drawing.Imaging.ImageFormat]::Png)

            return [pscustomobject]@{
                Path = $tempPath
                IsTemporary = $true
            }
        }
        finally {
            $graphics.Dispose()
            $resized.Dispose()
        }
    }
    finally {
        $image.Dispose()
    }
}

function Get-ImageOcrAnalysis {
    param([string]$ImagePath)

    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
        [Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
        [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null
        [Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
        [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
    }
    catch {
        throw "这台电脑没有可用的 Windows 本地图片文字识别组件。"
    }

    $engineList = New-Object System.Collections.Generic.List[object]
    $profileEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -ne $profileEngine) {
        $engineList.Add([pscustomobject]@{ Tag = "profile"; Engine = $profileEngine })
    }

    foreach ($language in [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) {
        $tag = $language.LanguageTag
        if ($tag -match '^(zh|en)') {
            try {
                $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
                if ($null -ne $engine) {
                    $engineList.Add([pscustomobject]@{ Tag = $tag; Engine = $engine })
                }
            }
            catch {
            }
        }
    }

    if ($engineList.Count -eq 0) {
        throw "没有找到可用的 OCR 语言包。请在 Windows 设置里安装中文或英文 OCR/语言功能后再试。"
    }

    $ocrImage = Get-OcrReadyImagePath -ImagePath $ImagePath
    $stream = $null

    try {
        $file = Await-WinRtOperation -Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ocrImage.Path)) -ResultType ([Windows.Storage.StorageFile])
        $stream = Await-WinRtOperation -Operation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) -ResultType ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await-WinRtOperation -Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) -ResultType ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-WinRtOperation -Operation ($decoder.GetSoftwareBitmapAsync()) -ResultType ([Windows.Graphics.Imaging.SoftwareBitmap])

        if ($bitmap.PixelWidth -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or $bitmap.PixelHeight -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension) {
            throw "图片太大，Windows OCR 无法直接识别。请先截取课表区域，或把图片缩小后再导入。"
        }

        $result = $null
        $bestScore = -1
        foreach ($engineInfo in $engineList) {
            try {
                $candidate = Await-WinRtOperation -Operation ($engineInfo.Engine.RecognizeAsync($bitmap)) -ResultType ([Windows.Media.Ocr.OcrResult])
                $score = 0
                if ($candidate.Text) {
                    $score += $candidate.Text.Length
                    if ($candidate.Text -match '[\u4e00-\u9fff]') { $score += 80 }
                }
                $score += (@($candidate.Lines).Count * 10)
                if ($score -gt $bestScore) {
                    $bestScore = $score
                    $result = $candidate
                }
            }
            catch {
            }
        }

        if ($null -eq $result) {
            throw "OCR 识别失败。请确认 Windows 已安装中文或英文 OCR/语言功能。"
        }

        Ensure-ScheduleImageAnalyzer
        $greenBlocks = [ScheduleImageAnalyzer]::FindGreenBlocks($ocrImage.Path)

        $recognizedLines = New-Object System.Collections.Generic.List[string]
        $lineObjects = New-Object System.Collections.Generic.List[object]
        foreach ($line in $result.Lines) {
            $words = @($line.Words)
            if ($words.Count -eq 0) { continue }

            if ($line.Text) {
                $recognizedLines.Add($line.Text)
            }
            else {
                $wordTexts = @()
                foreach ($word in $line.Words) {
                    $wordTexts += $word.Text
                }
                if ($wordTexts.Count -gt 0) {
                    $recognizedLines.Add(($wordTexts -join " "))
                }
            }

            $left = ($words | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
            $top = ($words | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
            $right = ($words | ForEach-Object { $_.BoundingRect.X + $_.BoundingRect.Width } | Measure-Object -Maximum).Maximum
            $bottom = ($words | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum

            $lineObjects.Add([pscustomobject]@{
                Text = $line.Text
                Left = [double]$left
                Top = [double]$top
                Right = [double]$right
                Bottom = [double]$bottom
                CenterX = ([double]$left + [double]$right) / 2
                CenterY = ([double]$top + [double]$bottom) / 2
            })
        }

        $text = if ($recognizedLines.Count -eq 0) { $result.Text } else { $recognizedLines -join "`r`n" }

        return [pscustomobject]@{
            Text = Repair-OcrScheduleText $text
            Lines = $lineObjects
            Blocks = $greenBlocks
            Width = $bitmap.PixelWidth
            Height = $bitmap.PixelHeight
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if ($null -ne $ocrImage -and $ocrImage.IsTemporary) {
            Remove-Item -LiteralPath $ocrImage.Path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Convert-OcrGridToScheduleText {
    param(
        [object]$Analysis,
        [int]$Year
    )

    $dayPattern = '^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|星期一|星期二|星期三|星期四|星期五|星期六|星期日|星期天|周一|周二|周三|周四|周五|周六|周日|周天|週一|週二|週三|週四|週五|週六|週日|週天)$'
    $datePattern = '(?i)\b(Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December)\s+\d{1,2}\b|\b\d{1,2}\s*月\s*\d{1,2}\s*(日|号|號)?\b'

    $dayLines = @($Analysis.Lines | Where-Object { $_.Text.Trim() -match $dayPattern -and $_.Top -lt ($Analysis.Height * 0.2) } | Sort-Object CenterX)
    $dateLines = @($Analysis.Lines | Where-Object { $_.Text.Trim() -match $datePattern -and $_.Top -lt ($Analysis.Height * 0.2) } | Sort-Object CenterX)
    if ($dateLines.Count -lt 2 -and $dayLines.Count -lt 2) { return "" }

    $days = New-Object System.Collections.Generic.List[object]
    if ($dateLines.Count -ge 2) {
        foreach ($dateLine in $dateLines) {
            $dateLabel = ([regex]::Match($dateLine.Text, $datePattern)).Value
            $nearestDay = $dayLines |
                Sort-Object @{ Expression = { [Math]::Abs($_.CenterX - $dateLine.CenterX) + [Math]::Abs($_.Top - $dateLine.Top) } } |
                Select-Object -First 1

            $dayName = ""
            if ($nearestDay -and [Math]::Abs($nearestDay.CenterX - $dateLine.CenterX) -lt ($Analysis.Width / 12)) {
                $dayName = $nearestDay.Text.Trim()
            }

            if ($dayName -eq "") {
                try {
                    $dateInfo = Parse-ScheduleDateLine -Line $dateLabel -Year $Year
                    if (-not $dateInfo.Success) { throw "date" }
                    $parsedDate = $dateInfo.Date
                    $dayName = $parsedDate.ToString("dddd", [Globalization.CultureInfo]::GetCultureInfo("en-US"))
                }
                catch {
                    $dayName = "Day"
                }
            }

            $days.Add([pscustomobject]@{
                Day = $dayName
                DateLabel = $dateLabel
                CenterX = $dateLine.CenterX
            })
        }
    }
    else {
        foreach ($dayLine in $dayLines) {
            $nearestDate = $dateLines |
                Sort-Object @{ Expression = { [Math]::Abs($_.CenterX - $dayLine.CenterX) + [Math]::Abs($_.Top - $dayLine.Top) } } |
                Select-Object -First 1

            $dateLabel = if ($nearestDate) { ([regex]::Match($nearestDate.Text, $datePattern)).Value } else { "" }
            $days.Add([pscustomobject]@{
                Day = $dayLine.Text.Trim()
                DateLabel = $dateLabel
                CenterX = $dayLine.CenterX
            })
        }
    }

    $days = @($days | Sort-Object CenterX)
    if ($days.Count -lt 2) { return "" }

    $blocks = @($Analysis.Blocks | Where-Object { $_.Top -gt ($Analysis.Height * 0.08) } | Sort-Object Top, Left)
    if ($blocks.Count -eq 0) { return "" }

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($block in $blocks) {
        $blockCenterX = ($block.Left + $block.Right) / 2
        $day = $days |
            Sort-Object @{ Expression = { [Math]::Abs($_.CenterX - $blockCenterX) } } |
            Select-Object -First 1

        if (-not $day -or $day.DateLabel -eq "") { continue }

        $insideLines = @(
            $Analysis.Lines |
                Where-Object {
                    $_.CenterX -ge ($block.Left - 15) -and $_.CenterX -le ($block.Right + 15) -and
                    $_.CenterY -ge ($block.Top - 15) -and $_.CenterY -le ($block.Bottom + 15)
                } |
                Where-Object {
                    $_.Text.Trim() -ne "" -and
                    $_.Text.Trim() -notmatch $dayPattern -and
                    $_.Text.Trim() -notmatch $datePattern
                } |
                Sort-Object Top, Left
        )

        if ($insideLines.Count -lt 2) { continue }

        $cleanLines = @($insideLines | ForEach-Object { Repair-OcrCourseText $_.Text } | Where-Object { $_ -ne "" })
        if ($cleanLines.Count -lt 2) { continue }

        $timeRange = Convert-OcrTimeRangeText ($cleanLines -join " ")
        if ($null -eq $timeRange) { continue }

        $title = $null
        foreach ($line in $cleanLines) {
            if ($line -notmatch '(?i)\b(AM|PM)\b' -and $line -notmatch '(?i)^Room\b' -and $line -notmatch '^(AC|LIB|Yard|OSY)') {
                $title = $line
                break
            }
        }
        if ($null -eq $title) { $title = $cleanLines[0] }

        $locationParts = New-Object System.Collections.Generic.List[string]
        foreach ($line in $cleanLines) {
            if ($line -eq $title) { continue }
            if ($line -match '(?i)\b(AM|PM)\b') { continue }
            $locationParts.Add($line)
        }

        $location = ($locationParts -join ", ")
        $location = [regex]::Replace($location, '(?i)^Room\s*[:\-.]?\s*', '')
        $location = $location.Trim(" -,.:")
        if ($location.Trim() -eq "") { $location = "Unknown" }

        $events.Add([pscustomobject]@{
            DateLine = "$($day.Day), $($day.DateLabel)"
            Title = $title
            TimeRange = $timeRange
            Location = $location
            SortX = $block.Left
            SortY = $block.Top
        })
    }

    if ($events.Count -eq 0) { return "" }

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($group in ($events | Sort-Object SortX, SortY | Group-Object DateLine)) {
        $output.Add($group.Name)
        foreach ($event in ($group.Group | Sort-Object SortY)) {
            $output.Add($event.Title)
            $output.Add($event.TimeRange)
            $output.Add("Room: $($event.Location)")
        }
    }

    return ($output -join "`r`n")
}

function Get-TextFromImage {
    param([string]$ImagePath, [int]$Year = (Get-Date).Year)

    $analysis = Get-ImageOcrAnalysis -ImagePath $ImagePath
    $gridText = Convert-OcrGridToScheduleText -Analysis $analysis -Year $Year
    if ($gridText.Trim() -ne "") {
        return $gridText
    }

    return $analysis.Text
}

function Get-PreviewText {
    param(
        [string]$Text,
        [int]$Year
    )

    $result = Convert-ScheduleTextToEvents -Text $Text -Year $Year

    if ($result.Events.Count -eq 0) {
        return [pscustomobject]@{
            Result = $result
            Text = "还没有识别到课程。请检查格式是否类似：`r`nMonday, Jan 28`r`nGE 2410 Lecture`r`n2:00 PM - 4:50 PM`r`nRoom: Classroom, AC3-214"
        }
    }

    $previewLines = New-Object System.Collections.Generic.List[string]
    $previewLines.Add("已识别 $($result.Events.Count) 节课：")
    foreach ($event in $result.Events) {
        $previewLines.Add("$($event.Start.ToString('yyyy-MM-dd HH:mm')) - $($event.End.ToString('HH:mm'))  $($event.Title)  $($event.Location)")
    }

    if ($result.Warnings.Count -gt 0) {
        $previewLines.Add("")
        $previewLines.Add("提醒：")
        foreach ($warning in $result.Warnings) {
            $previewLines.Add("- $warning")
        }
    }

    return [pscustomobject]@{
        Result = $result
        Text = ($previewLines -join "`r`n")
    }
}

function Get-ExportResult {
    param(
        [string]$Text,
        [int]$Year,
        [System.Collections.IEnumerable]$ConfirmedEvents,
        [string]$ConfirmedText,
        [object]$ConfirmedYear
    )

    if ($null -ne $ConfirmedEvents -and $Text -eq $ConfirmedText -and $Year -eq $ConfirmedYear) {
        return [pscustomobject]@{
            Events = $ConfirmedEvents
            Warnings = New-Object System.Collections.Generic.List[string]
        }
    }
    return Convert-ScheduleTextToEvents -Text $Text -Year $Year
}

function Convert-EventsToScheduleText {
    param([System.Collections.IEnumerable]$Events)

    $lines = New-Object System.Collections.Generic.List[string]
    $currentDate = $null
    foreach ($event in ($Events | Sort-Object Start, Title)) {
        $dateKey = $event.Start.ToString("yyyy-MM-dd")
        if ($dateKey -ne $currentDate) {
            $lines.Add((Convert-DateLineToScheduleHeader -Date $event.Start))
            $currentDate = $dateKey
        }

        $lines.Add($event.Title)
        $lines.Add("$($event.Start.ToString('h:mm tt', [Globalization.CultureInfo]::GetCultureInfo('en-US'))) - $($event.End.ToString('h:mm tt', [Globalization.CultureInfo]::GetCultureInfo('en-US')))")
        $lines.Add("Room: $($event.Location)")
    }

    return ($lines -join "`r`n")
}

function Copy-EventsForEditing {
    param([System.Collections.IEnumerable]$Events)

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($event in $Events) {
        $items.Add([pscustomobject]@{
            Title = [string]$event.Title
            Start = [datetime]$event.Start
            End = [datetime]$event.End
            Location = [string]$event.Location
            SourceDate = [string]$event.SourceDate
        })
    }

    return ,$items
}

function Get-EventsFromGrid {
    param([System.Windows.Forms.DataGridView]$Grid)

    $events = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Grid.Rows) {
        if ($row.IsNewRow) { continue }

        $title = [string]$row.Cells["Title"].Value
        $dateText = [string]$row.Cells["Date"].Value
        $startText = [string]$row.Cells["StartTime"].Value
        $endText = [string]$row.Cells["EndTime"].Value
        $location = [string]$row.Cells["Location"].Value

        if ([string]::IsNullOrWhiteSpace($title) -and [string]::IsNullOrWhiteSpace($dateText) -and
            [string]::IsNullOrWhiteSpace($startText) -and [string]::IsNullOrWhiteSpace($endText) -and
            [string]::IsNullOrWhiteSpace($location)) { continue }
        if ([string]::IsNullOrWhiteSpace($title)) { throw "课程名称不能为空。" }
        if ([string]::IsNullOrWhiteSpace($dateText)) { throw "日期不能为空。" }

        $date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($dateText.Trim(), "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) {
            throw "日期格式应为 yyyy-MM-dd：$title"
        }
        $startDate = Parse-TimeValue -Text $startText -Date $date
        $endDate = Parse-TimeValue -Text $endText -Date $date
        if ($null -eq $startDate -or $null -eq $endDate) { throw "无法识别时间：$title" }
        if ($endDate -le $startDate) { $endDate = $endDate.AddDays(1) }

        $events.Add([pscustomobject]@{
            Title = $title.Trim()
            Start = $startDate
            End = $endDate
            Location = if ($null -eq $location) { "" } else { $location.Trim() }
            SourceDate = Convert-DateLineToScheduleHeader -Date $date
        })
    }

    return ,$events
}

function Update-WeekTablePreview {
    param(
        [System.Windows.Forms.TableLayoutPanel]$WeekTable,
        [System.Collections.IEnumerable]$Events
    )

    $WeekTable.SuspendLayout()
    $WeekTable.Controls.Clear()
    $WeekTable.ColumnStyles.Clear()
    $WeekTable.RowStyles.Clear()
    $WeekTable.ColumnCount = 7
    $WeekTable.AutoScroll = $true

    $dayColumnWidth = [single](100.0 / 7.0)
    for ($i = 0; $i -lt 7; $i++) {
        [void]$WeekTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $dayColumnWidth)))
    }

    $orderedEvents = @($Events | Sort-Object Start, Title)
    if ($orderedEvents.Count -eq 0) {
        $WeekTable.RowCount = 0
        $WeekTable.ResumeLayout()
        return
    }

    $weekStarts = @($orderedEvents | ForEach-Object {
        $eventDate = $_.Start.Date
        $daysSinceMonday = (([int]$eventDate.DayOfWeek + 6) % 7)
        $eventDate.AddDays(-$daysSinceMonday)
    } | Sort-Object -Unique)
    $WeekTable.RowCount = $weekStarts.Count * 2
    foreach ($weekStart in $weekStarts) {
        [void]$WeekTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
        [void]$WeekTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
    }

    for ($weekIndex = 0; $weekIndex -lt $weekStarts.Count; $weekIndex++) {
        $weekStart = $weekStarts[$weekIndex]
        for ($i = 0; $i -lt 7; $i++) {
            $date = $weekStart.AddDays($i)
            $header = New-Object System.Windows.Forms.Label
            $header.Text = $date.ToString("ddd`nMM-dd", [Globalization.CultureInfo]::GetCultureInfo("zh-CN"))
            $header.Dock = "Fill"
            $header.TextAlign = "MiddleCenter"
            $header.BackColor = $script:CityURed
            $header.ForeColor = [System.Drawing.Color]::White
            $header.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
            $WeekTable.Controls.Add($header, $i, $weekIndex * 2)

            $dayPanel = New-Object System.Windows.Forms.FlowLayoutPanel
            $dayPanel.Dock = "Fill"
            $dayPanel.FlowDirection = "TopDown"
            $dayPanel.WrapContents = $false
            $dayPanel.AutoScroll = $true
            $dayPanel.BackColor = if ($i % 2 -eq 0) { [System.Drawing.Color]::White } else { $script:CityULightBlue }
            $dayEvents = @($orderedEvents | Where-Object { $_.Start.Date -eq $date })

            foreach ($event in $dayEvents) {
                $label = New-Object System.Windows.Forms.Label
                $label.AutoSize = $false
                $label.Width = 145
                $label.Height = 58
                $label.Margin = New-Object System.Windows.Forms.Padding(5)
                $label.Padding = New-Object System.Windows.Forms.Padding(5)
                $label.BackColor = $script:CityULightRed
                $label.ForeColor = $script:CityUText
                $label.BorderStyle = "FixedSingle"
                $label.Text = "$($event.Start.ToString('HH:mm'))-$($event.End.ToString('HH:mm'))`r`n$($event.Title)`r`n$($event.Location)"
                $dayPanel.Controls.Add($label)
            }

            $WeekTable.Controls.Add($dayPanel, $i, $weekIndex * 2 + 1)
        }
    }

    $WeekTable.ResumeLayout()
}

function Show-CourseReviewDialog {
    param(
        [System.Collections.IEnumerable]$Events,
        [System.Windows.Forms.Form]$Owner
    )

    $editableEvents = Copy-EventsForEditing -Events $Events
    if ($editableEvents.Count -eq 0) {
        return [pscustomobject]@{ Accepted = $false; Events = $Events }
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "确认课程日期和细节"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(1120, 760)
    $dialog.MinimumSize = New-Object System.Drawing.Size(980, 640)
    $dialog.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $dialog.BackColor = [System.Drawing.Color]::White

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(14)
    $layout.ColumnCount = 1
    $layout.RowCount = 4
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Label
    $header.Text = "请确认识别出的课程。可以直接修改日期、时间、课程名和地点。"
    $header.AutoSize = $true
    $header.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
    $header.ForeColor = $script:CityURed
    $header.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $layout.Controls.Add($header, 0, 0)

    $weekTable = New-Object System.Windows.Forms.TableLayoutPanel
    $weekTable.Dock = "Fill"
    $weekTable.CellBorderStyle = "Single"
    $layout.Controls.Add($weekTable, 0, 1)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = "Fill"
    $grid.AllowUserToAddRows = $true
    $grid.AllowUserToDeleteRows = $true
    $grid.AutoSizeColumnsMode = "Fill"
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.BorderStyle = "FixedSingle"
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $script:CityUDarkBlue
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
    $grid.EnableHeadersVisualStyles = $false
    $grid.SelectionMode = "FullRowSelect"

    [void]$grid.Columns.Add("Date", "日期")
    [void]$grid.Columns.Add("StartTime", "开始")
    [void]$grid.Columns.Add("EndTime", "结束")
    [void]$grid.Columns.Add("Title", "课程")
    [void]$grid.Columns.Add("Location", "地点")
    $grid.Columns["Date"].FillWeight = 85
    $grid.Columns["StartTime"].FillWeight = 65
    $grid.Columns["EndTime"].FillWeight = 65
    $grid.Columns["Title"].FillWeight = 170
    $grid.Columns["Location"].FillWeight = 190

    foreach ($event in ($editableEvents | Sort-Object Start, Title)) {
        [void]$grid.Rows.Add($event.Start.ToString("yyyy-MM-dd"), $event.Start.ToString("HH:mm"), $event.End.ToString("HH:mm"), $event.Title, $event.Location)
    }
    $layout.Controls.Add($grid, 0, 2)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.FlowDirection = "RightToLeft"
    $buttons.Dock = "Fill"
    $buttons.AutoSize = $true
    $buttons.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
    $layout.Controls.Add($buttons, 0, 3)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "确认并更新"
    $okButton.Width = 130
    $okButton.Height = 38
    $okButton.BackColor = $script:CityURed
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.FlatStyle = "Flat"
    $buttons.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "取消"
    $cancelButton.Width = 90
    $cancelButton.Height = 38
    $cancelButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 12, 3)
    $buttons.Controls.Add($cancelButton)

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = "刷新周表"
    $refreshButton.Width = 100
    $refreshButton.Height = 38
    $refreshButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 12, 3)
    $buttons.Controls.Add($refreshButton)

    Update-WeekTablePreview -WeekTable $weekTable -Events $editableEvents

    $refreshAction = {
        try {
            [void]$grid.EndEdit()
            $eventsFromGrid = Get-EventsFromGrid -Grid $grid
            Update-WeekTablePreview -WeekTable $weekTable -Events $eventsFromGrid
        }
        catch {
            Show-ResultDialog -Message $_.Exception.Message -Title "请检查课程信息" -Icon Warning
        }
    }
    $refreshButton.Add_Click($refreshAction)
    $grid.Add_CellEndEdit($refreshAction)

    $acceptedState = @{ Events = $null }
    $okButton.Add_Click({
        try {
            [void]$grid.EndEdit()
            $eventsFromGrid = Get-EventsFromGrid -Grid $grid
            if ($eventsFromGrid.Count -eq 0) { throw "没有可导出的课程。" }
            $acceptedState.Events = $eventsFromGrid
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
        catch {
            Show-ResultDialog -Message $_.Exception.Message -Title "请检查课程信息" -Icon Warning
        }
    })

    $cancelButton.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialogResult = $dialog.ShowDialog($Owner)
    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $null -ne $acceptedState.Events) {
        return [pscustomobject]@{ Accepted = $true; Events = $acceptedState.Events }
    }

    return [pscustomobject]@{ Accepted = $false; Events = $Events }
}

function Show-ResultDialog {
    param(
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(620, 360)
    $dialog.MinimumSize = New-Object System.Drawing.Size(520, 280)
    $dialog.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
    $dialog.BackColor = [System.Drawing.Color]::White

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(16)
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $dialog.Controls.Add($layout)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = $Title
    $titleLabel.AutoSize = $true
    $titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $script:CityURed
    $titleLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $layout.Controls.Add($titleLabel, 0, 0)

    $messageBox = New-Object System.Windows.Forms.TextBox
    $messageBox.Multiline = $true
    $messageBox.ReadOnly = $true
    $messageBox.ScrollBars = "Vertical"
    $messageBox.Dock = "Fill"
    $messageBox.Text = $Message
    $messageBox.BackColor = $script:CityULightBlue
    $messageBox.BorderStyle = "FixedSingle"
    $layout.Controls.Add($messageBox, 0, 1)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "确定"
    $okButton.Width = 96
    $okButton.Height = 36
    $okButton.Anchor = "Right"
    $okButton.BackColor = $script:CityURed
    $okButton.ForeColor = [System.Drawing.Color]::White
    $okButton.FlatStyle = "Flat"
    $okButton.Add_Click({ $dialog.Close() })
    $layout.Controls.Add($okButton, 0, 2)

    $dialog.AcceptButton = $okButton
    $dialog.ShowDialog() | Out-Null
}

if ($env:TIMETABLE_IMPORTER_NO_GUI -eq "1") {
    return
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "课表导入程序"
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(980, 720)
$form.Size = New-Object System.Drawing.Size(1120, 820)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$form.BackColor = [System.Drawing.Color]::White

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = "Fill"
$main.ColumnCount = 1
$main.RowCount = 5
$main.Padding = New-Object System.Windows.Forms.Padding(18)
$main.BackColor = [System.Drawing.Color]::White
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$form.Controls.Add($main)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "粘贴课表文字，或从图片识别，然后生成 Apple 日历 .ics 文件"
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = $script:CityURed
$titleLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$main.Controls.Add($titleLabel, 0, 0)

$settings = New-Object System.Windows.Forms.TableLayoutPanel
$settings.Dock = "Fill"
$settings.ColumnCount = 6
$settings.RowCount = 1
$settings.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 100)))
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$settings.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$main.Controls.Add($settings, 0, 1)

$yearLabel = New-Object System.Windows.Forms.Label
$yearLabel.Text = "年份"
$yearLabel.AutoSize = $true
$yearLabel.Anchor = "Left"
$yearLabel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$settings.Controls.Add($yearLabel, 0, 0)

$yearBox = New-Object System.Windows.Forms.NumericUpDown
$yearBox.Minimum = 2000
$yearBox.Maximum = 2100
$yearBox.Value = (Get-Date).Year
$yearBox.Width = 90
$yearBox.Anchor = "Left"
$settings.Controls.Add($yearBox, 1, 0)

$nameLabel = New-Object System.Windows.Forms.Label
$nameLabel.Text = "日历名称"
$nameLabel.AutoSize = $true
$nameLabel.Anchor = "Left"
$nameLabel.Margin = New-Object System.Windows.Forms.Padding(20, 0, 8, 0)
$settings.Controls.Add($nameLabel, 2, 0)

$nameBox = New-Object System.Windows.Forms.TextBox
$nameBox.Text = "课程表"
$nameBox.Dock = "Fill"
$settings.Controls.Add($nameBox, 3, 0)

$sampleButton = New-Object System.Windows.Forms.Button
$sampleButton.Text = "填入示例"
$sampleButton.AutoSize = $true
$sampleButton.FlatStyle = "Flat"
$settings.Controls.Add($sampleButton, 4, 0)

$imageButton = New-Object System.Windows.Forms.Button
$imageButton.Text = "从图片识别"
$imageButton.AutoSize = $true
$imageButton.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$imageButton.BackColor = $script:CityURed
$imageButton.ForeColor = [System.Drawing.Color]::White
$imageButton.FlatStyle = "Flat"
$settings.Controls.Add($imageButton, 5, 0)

$inputBox = New-Object System.Windows.Forms.TextBox
$inputBox.Multiline = $true
$inputBox.ScrollBars = "Both"
$inputBox.AcceptsReturn = $true
$inputBox.AcceptsTab = $true
$inputBox.WordWrap = $false
$inputBox.Dock = "Fill"
$inputBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$inputBox.BorderStyle = "FixedSingle"
$main.Controls.Add($inputBox, 0, 2)

$previewBox = New-Object System.Windows.Forms.TextBox
$previewBox.Multiline = $true
$previewBox.ReadOnly = $true
$previewBox.ScrollBars = "Vertical"
$previewBox.Dock = "Fill"
$previewBox.BackColor = $script:CityULightBlue
$previewBox.BorderStyle = "FixedSingle"
$previewBox.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 12)
$main.Controls.Add($previewBox, 0, 3)

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.FlowDirection = "RightToLeft"
$buttons.Dock = "Fill"
$buttons.AutoSize = $true
$main.Controls.Add($buttons, 0, 4)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = "生成 ICS 文件"
$exportButton.Width = 140
$exportButton.Height = 38
$exportButton.BackColor = $script:CityURed
$exportButton.ForeColor = [System.Drawing.Color]::White
$exportButton.FlatStyle = "Flat"
$buttons.Controls.Add($exportButton)

$editButton = New-Object System.Windows.Forms.Button
$editButton.Text = "编辑确认课程"
$editButton.Width = 130
$editButton.Height = 38
$editButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 12, 3)
$editButton.BackColor = $script:CityUDarkBlue
$editButton.ForeColor = [System.Drawing.Color]::White
$editButton.FlatStyle = "Flat"
$buttons.Controls.Add($editButton)

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "预览识别结果"
$previewButton.Width = 140
$previewButton.Height = 38
$previewButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 12, 3)
$previewButton.BackColor = $script:CityUDarkBlue
$previewButton.ForeColor = [System.Drawing.Color]::White
$previewButton.FlatStyle = "Flat"
$buttons.Controls.Add($previewButton)

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = "清空"
$clearButton.Width = 90
$clearButton.Height = 38
$clearButton.Margin = New-Object System.Windows.Forms.Padding(0, 3, 12, 3)
$clearButton.FlatStyle = "Flat"
$buttons.Controls.Add($clearButton)

$openReviewDialog = {
    param([System.Collections.IEnumerable]$Events, [string]$Prefix)

    if ($null -eq $Events -or @($Events).Count -eq 0) { return }

    $review = Show-CourseReviewDialog -Events $Events -Owner $form
    if ($review.Accepted) {
        $script:CurrentEvents = $review.Events
        $inputBox.Text = Convert-EventsToScheduleText -Events $script:CurrentEvents
        $script:CurrentEventsText = $inputBox.Text
        $script:CurrentEventsYear = [int]$yearBox.Value
        $preview = Get-PreviewText -Text $inputBox.Text -Year ([int]$yearBox.Value)
        $previewBox.Text = "$Prefix`r`n`r`n" + $preview.Text
    }
}

$sampleButton.Add_Click({
    $inputBox.Text = Get-SampleScheduleText -Year ([int]$yearBox.Value)
    $script:CurrentEvents = $null
    $script:CurrentEventsText = ""
    $script:CurrentEventsYear = $null
})

$imageButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "选择课表图片"
    $dialog.Filter = "图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif;*.tiff|所有文件|*.*"
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    if ($inputBox.Text.Trim() -ne "") {
        $replace = [System.Windows.Forms.MessageBox]::Show(
            "识别出的文字会替换当前输入框内容，是否继续？",
            "确认替换",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($replace -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }

    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $imageButton.Enabled = $false
        $previewBox.Text = "正在识别图片文字，请稍等..."
        [System.Windows.Forms.Application]::DoEvents()

        $recognizedText = Get-TextFromImage -ImagePath $dialog.FileName -Year ([int]$yearBox.Value)
        if ($recognizedText.Trim() -eq "") {
            $inputBox.Clear()
            $previewBox.Text = "没有从图片里识别到文字。请换一张更清晰的截图，尽量只截课表区域。"
            return
        }

        $inputBox.Text = $recognizedText
        $preview = Get-PreviewText -Text $inputBox.Text -Year ([int]$yearBox.Value)
        $previewBox.Text = "图片文字已识别。请先检查左侧文字是否有错。`r`n`r`n" + $preview.Text
        if ($preview.Result.Events.Count -gt 0) {
            & $openReviewDialog $preview.Result.Events "已确认课程，下面是更新后的结果："
        }
    }
    catch {
        $previewBox.Text = ""
        Show-ResultDialog -Message "图片识别失败：$($_.Exception.Message)" -Title "识别失败" -Icon Warning
    }
    finally {
        $imageButton.Enabled = $true
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})

$clearButton.Add_Click({
    $inputBox.Clear()
    $previewBox.Clear()
    $script:CurrentEvents = $null
    $script:CurrentEventsText = ""
    $script:CurrentEventsYear = $null
})

$previewButton.Add_Click({
    $preview = Get-PreviewText -Text $inputBox.Text -Year ([int]$yearBox.Value)
    $previewBox.Text = $preview.Text
    if ($preview.Result.Events.Count -gt 0) {
        & $openReviewDialog $preview.Result.Events "已确认课程，下面是更新后的结果："
    }
})

$editButton.Add_Click({
    $result = Convert-ScheduleTextToEvents -Text $inputBox.Text -Year ([int]$yearBox.Value)
    if ($result.Events.Count -eq 0) {
        Show-ResultDialog -Message "还没有识别到课程。请先粘贴课表文字、从图片识别，或点“预览识别结果”。" -Title "没有课程可编辑" -Icon Warning
        return
    }

    & $openReviewDialog $result.Events "已确认课程，下面是更新后的结果："
})

$exportButton.Add_Click({
    $result = Get-ExportResult -Text $inputBox.Text -Year ([int]$yearBox.Value) -ConfirmedEvents $script:CurrentEvents -ConfirmedText $script:CurrentEventsText -ConfirmedYear $script:CurrentEventsYear

    if ($result.Events.Count -eq 0) {
        Show-ResultDialog -Message "没有识别到课程。请先粘贴课表文字，或点“填入示例”看看格式。" -Title "无法生成" -Icon Warning
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = "保存 ICS 日历文件"
    $dialog.Filter = "iCalendar 文件 (*.ics)|*.ics"
    $dialog.FileName = "课程表-$([int]$yearBox.Value).ics"
    $dialog.OverwritePrompt = $true

    if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $calendarName = $nameBox.Text.Trim()
        if ($calendarName -eq "") { $calendarName = "课程表" }
        $ics = Convert-EventsToIcs -Events $result.Events -CalendarName $calendarName
        [System.IO.File]::WriteAllText($dialog.FileName, $ics, [System.Text.UTF8Encoding]::new($false))

        $message = "已生成：$($dialog.FileName)`r`n`r`n共导出 $($result.Events.Count) 节课。"
        if ($result.Warnings.Count -gt 0) {
            $message += "`r`n`r`n有 $($result.Warnings.Count) 条提醒，可在预览里查看。"
        }
        Show-ResultDialog -Message $message -Title "完成" -Icon Information
    }
    catch {
        Show-ResultDialog -Message "保存失败：$($_.Exception.Message)" -Title "出错了" -Icon Error
    }
})

$inputBox.Text = Get-SampleScheduleText -Year ([int]$yearBox.Value)

[void]$form.ShowDialog()
