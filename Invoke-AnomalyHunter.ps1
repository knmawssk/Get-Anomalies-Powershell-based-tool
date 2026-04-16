Import-Module ./Format-WinEvent.ps1

# 2026-04-02 added ConvertTo-DateTimeFormatted & ConvertFrom-DateTimeFormatted functions for simple CONSISTENT datetime formatting throughout entire project
function ConvertTo-DateTimeFormatted ([DateTime] $DateTime)
{
    # Ensure all datetime objects are formatted to culture-invariant syntax for consistent retrieval from $configFile.
    $formatString = "yyyy-MM-ddTHH:mm:ss.fffZ"
    $culture = [CultureInfo]::InvariantCulture

    return $DateTime.ToString($formatString, $culture)
}

function ConvertFrom-DateTimeFormatted ([String] $DateTime)
{
    # Ensure all datetime objects are formatted to culture-invariant syntax for consistent retrieval from $configFile.
    $culture = [CultureInfo]::InvariantCulture
write-host "[ConvertFrom-DateTimeFormatted] type=$($DateTime.GetType().Name), Value=$DateTime" -f magenta
    return [System.DateTime]::Parse($DateTime, $culture).ToUniversalTime()
}

function Get-FileName ([String] $LogName, [Int] $EID, [String[]] $Properties) 
{
    return "$($LogName.Replace('/','-'))_$($EID)_$($Properties -join '_').csv"
}

function Get-ExecHistoryFileName ([String] $LogName, [Int] $EID, [String[]] $Properties) 
{
    # return 'history_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
 
    $fileName = 'execHistory_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
    $fileDir = 'logs'
    if (-not(Test-Path -Path $fileDir))
    {
        New-Item -ItemType Directory -Name $fileDir | Out-Null
    }

    return (Join-Path $fileDir $fileName)
}

function Get-ResultHistoryFileName ([String] $LogName, [Int] $EID, [String[]] $Properties) 
{
    # return 'result_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
 
    $fileName = 'resultHistory_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
    $fileDir = 'results'
    if (-not(Test-Path -Path $fileDir))
    {
        New-Item -ItemType Directory -Name $fileDir | Out-Null
    }
    
    return (Join-Path $fileDir $fileName)
}

# 2026-04-02 added below which is COPY of Get-ResultHistoryFileName with slight naming update from resultHistory_ to anomalyHistory_
function Get-AnomalyHistoryFileName ([String] $LogName, [Int] $EID, [String[]] $Properties) 
{
    $fileName = 'anomalyHistory_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
    $fileDir = 'results'
    if (-not(Test-Path -Path $fileDir))
    {
        New-Item -ItemType Directory -Name $fileDir | Out-Null
    }
    
    return (Join-Path $fileDir $fileName)
}

function Get-StartTime ([String] $LogName, [Int] $EID, [String[]] $Properties)
{
    # TODO: define $filePath variable here by using input parameters $LogName, $EID and $Properties.
    # HINT: make a helper function called Get-FileName that returns this formatted file name with these same input parameters.

    $execHistoryFilePath = Get-ExecHistoryFileName -LogName $LogName -EID $EID -Properties $Properties

    Write-Host "[*] [Get-StartTime] `$execHistoryFilePath=" -NoNewline -ForegroundColor cyan
    Write-Host $execHistoryFilePath -ForegroundColor yellow

# $global:execHistoryFilePath = $execHistoryFilePath
# # DEBUGGING BELOW!!!
# if (-not $global:BLA)
# {
#     $global:BLA = [PSCustomObject] @{
#         IF = [PSCustomObject] @{
#             history = $null
#             startTime = $null
#         }
#         ELSE = [PSCustomObject] @{
#             oldestEventTime = $null
#             startTime = $null
#         }
#     }
# }


    if ((Test-Path $execHistoryFilePath) -eq $True)  
    { 
        # TODO-02: probably make below end with .maxTime and not .endTime
        # TODO-03: figure out 
#         $history = (Import-Csv $execHistoryFilePath | Sort-Object endTime -Descending | Select-Object -First 1).endTime
#         # $startTime = (Import-Csv $execHistoryFilePath | Sort-Object endTime -Descending | Select-Object -First 1).endTime

# # figure out oldest event time AFTER the above .maxTime (to avoid infinite loops if there are legitimately GAPS in event logs)
# # $oldestEventTime = (Get-WinEvent -Oldest -MaxEvents 1 -FilterHashtable @{LogName = $LogName; Id = $EID} | Select-Object TimeCreated | Select-Object -First 1).TimeCreated

#         $startTime = [System.DateTime]::Parse($history, [CultureInfo]::InvariantCulture)

        # ......No need to re-format since already in UTC string format when stored in $execHistoryFilePath.
        $startTime = (Import-Csv $execHistoryFilePath | Sort-Object endTime -Descending | Select-Object -First 1).endTime
        $startTime = ConvertFrom-DateTimeFormatted -DateTime $startTime

# $global:BLA.IF.history = $history
# $global:BLA.IF.startTime = $startTime

    }
    else
    {
        $oldestEventTime = (Get-WinEvent -Oldest -MaxEvents 1 -FilterHashtable @{LogName = $LogName; Id = $EID} | Select-Object TimeCreated | Select-Object -First 1).TimeCreated
        # TEMP_DBO_TESTING 2026-04-01
        # $oldestEventTime = ConvertTo-DateTimeFormatted -DateTime (Import-CliXml ./export_for_dbo.clixml | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
        # Write-Host "OldestEventTime is $($oldestEventTime.ToUniversalTime())" -ForegroundColor Magenta
        Write-Host "OldestEventTime is $($oldestEventTime)" -ForegroundColor Magenta
        # $startTime = [System.DateTime]::Parse($oldestEventTime.ToString(), (Get-Culture))
        # $startTime = ConvertTo-DateTimeFormatted -DateTime ([System.DateTime]::Parse($oldestEventTime.ToString(), (Get-Culture)))
        
        # TODO - you might be able to COMMENT below when using Get-WinEvent above...
        $startTime = ConvertFrom-DateTimeFormatted -DateTime $oldestEventTime

# $global:BLA.ELSE.oldestEventTime = $oldestEventTime
# $global:BLA.ELSE.startTime = $startTime

    }

    return $startTime
}


# 2026-04-02 getting NEWEST event in event log as cap for $EndTime to: 1) avoid querying for events in the future (and missing them during the next run) and 2) for automating hourly gap-filling by having an end datetime for which to stop looping
function Get-MaxEndTime ([String] $LogName, [Int] $EID, [String[]] $Properties)
{
    # By default Get-WinEvent returns events newest to oldest.
    $newestEventTime = (Get-WinEvent -MaxEvents 1 -FilterHashtable @{LogName = $LogName; Id = $EID} | Select-Object TimeCreated | Select-Object -First 1).TimeCreated
    # TEMP_DBO_TESTING 2026-04-01
    # $newestEventTime = ConvertTo-DateTimeFormatted -DateTime (Import-CliXml ./export_for_dbo.clixml | Sort-Object TimeCreated | Select-Object -Last 1).TimeCreated
    Write-Host "NewestEventTime is $($newestEventTime)" -ForegroundColor Magenta
    # $maxEndTime = [System.DateTime]::Parse($newestEventTime.ToString(), (Get-Culture))
    # $startTime = ConvertTo-DateTimeFormatted -DateTime ([System.DateTime]::Parse($oldestEventTime.ToString(), (Get-Culture)))

    $maxEndTime = ConvertFrom-DateTimeFormatted -DateTime $newestEventTime

    return $maxEndTime
}




function Invoke-AnomalyHunter ([String] $LogName, [Int] $EID, [String[]] $Properties, [DateTime] $StartTime, [DateTime] $EndTime) 
{
    # 2026-04-02 CONSISTENTLY format timestamps at beginning of function to avoid confusion in debug output.
    # Ensure all datetime objects are formatted to culture-invariant syntax for consistent retrieval from $configFile.
    # $formatString = "yyyy-MM-ddTHH:mm:ss.fffZ"
    # $culture = [CultureInfo]::InvariantCulture
    # $executionTimeFormatted = (Get-Date).ToString($formatString, $culture)
    # $startTimeFormatted = $StartTime.ToString($formatString, $culture)
    # $endTimeFormatted = $EndTime.ToString($formatString, $culture)
    $executionTimeFormatted = ConvertTo-DateTimeFormatted -DateTime (Get-Date)
    $startTimeFormatted = ConvertTo-DateTimeFormatted -DateTime $StartTime
    $endTimeFormatted = ConvertTo-DateTimeFormatted -DateTime $EndTime

    # STEP 3: Querying event logs for current grouping.
    # Write-Host "[*] Using Get-WinEvent to query from $StartTime to $EndTime" -f cyan
    Write-Host "[*] Using Get-WinEvent to query from $startTimeFormatted to $endTimeFormatted" -f cyan
    $events = (Get-WinEvent -FilterHashtable @{LogName = $LogName; Id = $EID ; startTime = $StartTime; endTime = $EndTime} -errorAction SilentlyContinue)
    # TEMP_DBO_TESTING 2026-04-01
    # $events = (Import-CliXml ./export_for_dbo.clixml | Where-Object { $_.TimeCreated -ge $StartTime -and $_.TimeCreated -le $EndTime })
    # TODO-02: use try-catch block to gracefully handle "error" when no event logs are found
    # TODO-02: -ErrorAction might be an option for Get-WinEvent

    # STEP 4: Group queried event logs by value(s) in $Properties.
    $eventsGrouped = $events | Format-WinEvent | ForEach-Object { $_.Props } | Group-Object $Properties
    Write-Host "[*] $($events.Count) events were grouped into $($eventsGrouped.Count) group(s)..." -f cyan

    # STEP 5: Compare current grouped events with previous result history for current properties (if exists).

    $eventGroupedHistory = @() 
    $resultHistoryFilePath = Get-ResultHistoryFileName -LogName $LogName -EID $EID -Properties $Properties 
    Write-Host "`$resultHistoryFilePath=$resultHistoryFilePath" -f yellow 
    if ((Test-Path $resultHistoryFilePath) -eq $True)   
    { 
        $eventGroupedHistory = [PSCustomObject[]] (Import-Csv $resultHistoryFilePath) 
        Write-Host "FOUND FILE PATH: `$resultHistoryFilePath=$resultHistoryFilePath...count=$($eventGroupedHistory.Count)" -f yellow 
    }

# temp global variable for easier debugging purposes...
$global:comparisonResultArr = $comparisonResultArr

    # TODO - does below function RETURN results? or does it just output to disk INSIDE the function? TBD...
    Write-Host "[*] STARTING call Compare-EventGrouped..." -f yellow
    $comparisonResultArr = Compare-EventGrouped -EventsGrouped $eventsGrouped -EventGroupedHistory $eventGroupedHistory
    Write-Host "[*] FINISHING call Compare-EventGrouped...`$comparisonResultArr.Count=$($comparisonResultArr.Count)" -f yellow
    $anomalyArr = $comparisonResultArr | Where-Object {$_.isAnomaly -eq $True}
    $anomalyCount = ($comparisonResultArr | Where-Object {$_.isAnomaly -eq $True}).Count 
    $nonAnomalyCount = $eventsGrouped.Count - $anomalyArr.Count 
    Write-Host "[*] Anomaly Count is $anomalyCount" 
    Write-Host "[*] Non anomaly Count is $nonAnomalyCount" 
    Write-Host "[*] $anomalyCount + $nonAnomalyCount = $($eventsGrouped.Count) ??? $(($anomalyCount + $nonAnomalyCount) -eq $eventsGrouped.Count)" -f cyan
    # $anomalyCount = $anomalyArr.Count
    # Write-Host "[*] Anomaly Count is $anomalyCount"

    # $nonAnomalyArr = $comparisonResultArr | Where-Object {$_.isAnomaly -eq $False}
    # # TODO-02: I think isAnomaly does not exist in history, so below should be correct (but test it!)
    # #$nonAnomalyArr = $comparisonResultArr | Where-Object {-not $_.isAnomaly}
    # # $nonAnomalyArr = $comparisonResultArr | Where-Object {-not ($_.isAnomaly -eq $True)}
    # $nonAnomalyCount = $nonanomalyArr.Count
    # Write-Host "[*] Non anomaly Count is $nonAnomalyCount"
    # Write-Host "[*] $($anomalyArr.Count) + $($nonanomalyArr.Count) = $($eventsGrouped.Count) ??? $(($anomalyArr.Count + $nonanomalyArr.Count) -eq $eventsGrouped.Count)" -f cyan
    # TODO: output statistics from Compare-EventGrouped stored in $comparisonResultArr
    # TODO: output results to DISK from Compare-EventGrouped stored in $comparisonResultArr



# TODO 2026-04-02 - probably only update HISTORY file here if successfully reached the end of this function


    # Ensure all datetime objects are converted to UTC for consistency across timezones.
    #$StartTime = $StartTime.ToUniversalTime()
    #$EndTime = $EndTime.ToUniversalTime()
    #$executionTime = (Get-Date).ToUniversalTime()
    # TODO: ^^^ commented for now, but likely need to re-introduce after finding datetime bug :/

# NOTES - 2026-04-02 - this $executionTime variable was being used but no longer exists/is set in the code. This can happen when you have a loooooong PowerShell session where an older version of the variable still exists in memory...but creating a NEW powershell process shows that the variable is not actually being created in the code.
    # Store current time of execution.
    # $executionTime = Get-Date

    # Create execution history object to store statistics of current execution for retrieval during next execution.
    $eventTimeArrSorted = $events.TimeCreated | Sort-Object -Unique
    $minTime = ""
    $maxTime = ""
    if ($eventTimeArrSorted.Count -gt 0) {
        $minTime = (ConvertTo-DateTimeFormatted -DateTime ($eventTimeArrSorted | Select-Object -First 1))
        $maxTime = (ConvertTo-DateTimeFormatted -DateTime ($eventTimeArrSorted | Select-Object -Last 1))
    }

    $execHistoryObj = [PSCustomObject] @{
        executionTime = $executionTimeFormatted
        startTime = $startTimeFormatted
        endTime = $endTimeFormatted
        #
# NOTES - 2026-04-02 - added below to track inner bookend timestamps of events found INSIDE startTime-endTime time range
        minTime = $minTime
        maxTime = $maxTime
        #minTime = ($eventTimeArrSorted ? (ConvertTo-DateTimeFormatted -DateTime ($eventTimeArrSorted | Select-Object -First 1)) : '')
        #maxTime = ($eventTimeArrSorted ? (ConvertTo-DateTimeFormatted -DateTime ($eventTimeArrSorted | Select-Object -Last 1)) : '')
# NOTES - 2026-04-02 - added below to track event count and GROUPED event count for each execution history record
        eventCount = $events.Count
        eventGroupedCount = $eventsGrouped.Count
    }

# NOTES - 2026-04-02 - MOVED THIS to end of function so we can include event counts...
    # STEP ???: Output execution and start/end times for current grouping (if successful).
    $execHistoryFilePath = Get-ExecHistoryFileName -LogName $LogName -EID $EID -Properties $Properties
    $execHistoryObj | Export-Csv -Path $execHistoryFilePath -Append
    Write-Host "[*] Exported `$execHistoryFilePath=$execHistoryFilePath"




    # DONE: probably need to DROP isAnomaly property for this before outputing to CSV...
    # $comparisonResultArr | ForEach-Object { $_.PSObject.Properties.Remove('isAnomaly') }
# NOTES - 2026-04-02 - avoid errors if any of the below variables are empty/null by adding IF block first.
    
    # Update complete resultHistory file for current final comparison results.
    if ($comparisonResultArr)
    {
        $comparisonResultArr | Select-Object minTime, maxTime, eventCount, key | Export-Csv -Path $resultHistoryFilePath
    }

    # Append any anomalies to anomalyHistory file.
    if ($anomalyArr)
    {
        $anomalyHistoryFilePath = Get-AnomalyHistoryFileName  -LogName $LogName -EID $EID -Properties $Properties
        $anomalyArr | Export-Csv -Path $anomalyHistoryFilePath -Append

        # $anomalyArr | Export-Csv -Path "history_of_detected_anomalies_$(Get-FileName -LogName $LogName -EID $EID -Properties $Properties)" -Append #updating csv with anomalies and adding it all to one list - not overriding
    }
# NOTES - 2026-04-02 - I think we can skip outputting the below file since it isn't necessary
    # if ($nonAnomalyArr)
    # {
    #     $nonAnomalyArr | Export-Csv -Path "comparison_between_old_and_new_file_$(Get-FileName -LogName $LogName -EID $EID -Properties $Properties)" -Append #updating csv with normal events
    # }
}

# function Compare-EventGrouped ([String] $LogName, [Int] $EID, [String[]] $Properties)
# TODO-02: if you want to do property stuff dynamically, you'll need to pass in [String[]] $Properties here...
function Compare-EventGrouped ([PSCustomObject[]] $EventsGrouped, [PSCustomObject[]] $EventGroupedHistory)
{
    Write-Host "`n`n[*] Starting Compare-EventGrouped: `$EventsGrouped.Count=$($EventsGrouped.Count) & `$EventGroupedHistory.Count=$($EventGroupedHistory.Count)" -f Magenta
    #arrays
    $eventsGroupedObjArr = @()
    $anomalyHistory = @() #for storing anomalies
    $nonAnomalyComparisonHistory = @() #for comparison of new and old file with non-anomalies

    #creating variables for counting anomalous and non anomalous activity
    $matchedEventCount = 0
    $anomalyCount = 0

    # $resultHistoryFilePath = Get-ResultHistoryFileName -LogName $LogName -EID $EID -Properties $Properties
    # if ((Test-Path $resultHistoryFilePath) -eq $True)  
    # {
    #     # $eventGroupedHistory = (Import-Csv 'EID_1_ParentImage_Image.csv')
    #     $eventGroupedHistory = [PSCustomObject[]] (Import-Csv $resultHistoryFilePath)
    # }

    #loop for retrieving events
    for ($i=0; $i -lt $EventsGrouped.Count; $i++)
    {
        $curGroup = $EventsGrouped[$i]

        # Write-Host "is this is single-string properties? `$curGroup.Name=$($curGroup.Name)" -f magenta # should be a single string with ALL the properties defined in Group-Object ($Properties)

        $timeBounds = $curGroup.Group | Select-Object Image, UtcTime | Measure-Object -Minimum -Maximum -Property UtcTime
        $minTime = $timeBounds.Minimum
        $maxTime = $timeBounds.Maximum
        $eventCount = $curGroup.Count
        $keyName = $curGroup.Name # this is the single string of the $Properties used in Group-Object outside this function

        # # Dynamically extract $Properties from first grouped event.
        # $firstElement = $curGroup.Group[0]
        # $parentImage = $firstElement.ParentImage
        # $Image = $firstElement.Image

        # Write-Host "[*] From time $minTime to $maxTime, there were $eventCount occurrences of ParentImage $parentImage and Image $Image" -f cyan
        Write-Host "[*] From time $minTime to $maxTime, there were $eventCount occurrences of keyName=$keyName" -f cyan
        
        $curGroupObj = [PSCustomObject] @{
            # Add boolean property to easily label if current grouping is an anomaly (default to $false).
            isAnomaly = $false
            minTime = $minTime
            maxTime = $maxTime
            eventCount = $eventCount
# TODO: make dynamic for ANY NUMBER of properties.
            # parentimage = $parentImage
            # image = $Image
            key = $keyName
            # add execution time
        }

        #CLI output
        # Write-Host "Starting to search for anomalies..."

        #comparing new ver with old one
        # DONE: make dynamic for ANY NUMBER of properties.
        # $curGroupHistoryObj = $EventGroupedHistory | Where-Object {
        #     for ($k=0; $k -le ($Properties.Count-1); k++) {
        #         $_.($Properties[$k]) -eq $curGroupObj.($Properties[$k])
        #     }
        # }
        # Look for history objects that have the same key ($Properties as a single string) as our current grouped events.
        # $curGroupHistoryObj = $EventGroupedHistory | Where-Object { $_.key -eq $keyName }
        # $curGroupHistoryObj = ($EventGroupedHistory | Where-Object { $_.key -eq $keyName })[0]
        $curGroupHistoryObj = $EventGroupedHistory | Where-Object { $_.key -eq $keyName } | Select-Object -First 1
        #     $_.($Properties[0]) -eq $curGroupObj.($Properties[0]) -and
        #     $_.($Properties[1]) -eq $curGroupObj.($Properties[1])
        # } | Select-Object -First 1

        if ($curGroupHistoryObj -ne $null)
        {
            # Write-Host 'Match was found' -f green
            $matchedEventCount=$matchedEventCount+1

            # Write-Host "Event count of old result is $($curGroupHistoryObj.eventCount) and event count of new result $($curGroupObj.eventCount)"
            # #output both events
            # Write-Host "[*] Event from the old file has image: $($curGroupHistoryObj.image) and parent image $($curGroupHistoryObj.parentimage), and event from new run has image: $($curGroupObj.Image) and parent image $($curGroupObj.ParentImage)"
            # Write-Host "Number of events after merging is $($curGroupHistoryObj.eventCount)"

            #storing it in array for comparison purposes
            $nonanomalycomparison = [PSCustomObject] @{
                #adding those to compare old and new
                minTime_oldfile = $curGroupHistoryObj.minTime
                minTime_newfile = $curGroupObj.minTime
                maxTime_oldfile = $curGroupHistoryObj.maxTime
                maxTime_newfile = $curGroupObj.maxTime
                eventCount_oldfile = $curGroupHistoryObj.eventCount
                eventCount_newfile = $curGroupObj.eventCount

                # TODO: avoid hardcoding below property names using Add-Member cmdlet
                parentimage = $curGroupObj.parentImage #check here
                image = $curGroupObj.Image
            }

            $nonAnomalyComparisonHistory += $nonanomalycomparison #change

            # Update current grouping history object with statistics from current grouping.
            # $curGroupHistoryObj.isAnomaly = $false
            $curGroupHistoryObj | Add-Member -MemberType NoteProperty -Name 'isAnomaly' -Value $false
            $curGroupHistoryObj.minTime = @($curGroupHistoryObj.minTime, $curGroupObj.minTime) | Sort-Object | Select-Object -First 1
            $curGroupHistoryObj.maxTime = @($curGroupHistoryObj.maxTime, $curGroupObj.maxTime) | Sort-Object | Select-Object -Last 1
            $curGroupHistoryObj.eventCount = $curGroupObj.eventCount + $curGroupHistoryObj.eventCount
            # Write-Host "Min Time is $($curGroupHistoryObj.minTime) and MaxTime is $($curGroupHistoryObj.maxTime)"
        }
        #elseif ($curGroupHistoryObj -eq $null)
        else
        {
            # If current grouping is NEW then update boolean flag to an anomaly.
            $curGroupObj.isAnomaly = $true

            # Write-Host "Match was not found. Anomalous behaviour" -f red
            $EventGroupedHistory += $curGroupObj #just adding to usual file
            $anomalyCount = $anomalyCount+1 #summing to get the number of anomalies
            # $anomalyHistory += $curGroupObj #adding to anomalies list only, ADD CURRENT TIME!!!! + ADD EXECUTION TIME OF THE ANOMALY

        }
        #$eventsGroupedObjArr += $curGroupObj
    }

    Write-Host "Number of anomalies detected is $anomalyCount"
    Write-Host "Number of 'normal' events is $matchedEventCount" 

# TODO: figure out WHAT this function should DO/RETURN...
# probably should return a special PSCustomObject[] with information about anomalies, etc.
# we PROBABLY want to move the below Export-Csv OUTSIDE this function so this function ONLY compares (and does NOT write to disk)
    return $EventGroupedHistory
}









@([PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('ParentImage', 'Image')},[PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('User','Image','CommandLine')}, [PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('User','Image')} ) | ConvertTo-Json | Set-Content config.json
$configJson = Get-Content -Path config.json | ConvertFrom-Json 
foreach ($config in $configJson) 
{ 
    # STEP 1: Extract properties for grouping from current config. 
    $logName = $config.LogName 
    $eid = $config.EID 
    $properties = $config.properties

# STEP 1: Define properties for current grouping.
# # Define properties for current grouping (e.g. LogName, EID and Properties).
# $LogName = "Microsoft-Windows-Sysmon/Operational"
# $EID = 1
# $Properties = @('ParentImage', 'Image')
# # $Properties = @('User','Image','CommandLine')
# # $Properties = @('User','Image')
# # $Properties.Count

# STEP 2: Retrieve start/end times for querying event logs for current grouping.

# Define bin size for frequency.
# TODO - probably define this value in a CENTRAL CONFIG in the project so it will match the FREQUENCY of the scheduled service for scheduling execution of Invoke-AnomalyHunter.
$binSizeInMin = 60 * 6

do
{
    # Retrieve start time and end time for current run.
    $startTime = Get-StartTime -LogName $LogName -EID $EID -Properties $Properties
    $endTime = $startTime.AddMinutes($binSizeInMin)

    # Ensure end time does not exceed maximum possible end time in event logs.
    $maxEndTime = Get-MaxEndTime -LogName $LogName -EID $EID -Properties $Properties
    # $endTime = $endTime -lt $maxEndTime ? $endTime : $maxEndTime
    if ($endTime -gt $maxEndTime) { $endTime = $maxEndTime }

    Write-Host "[*] Invoke-AnomalyHunter -StartTime $startTime -EndTime $endTime" -f green
    Invoke-AnomalyHunter -LogName $LogName -EID $EID -Properties $Properties -StartTime $startTime -EndTime $endTime

    Write-Host "`n`n[*] DO WHILE ($endTime -lt $maxEndTime)...`n`n" -f cyan
    Start-Sleep -Seconds 2
}
while ($endTime -lt $maxEndTime)
}

#Getting path name for task scheduling and deletion process
function Get-PathName ($NameOfFile) {
    $pwdd = Get-Location
    return "$($pwdd)/$($NameOfFile)"
}

#declaring files that we have:
$Code = 'Invoke-AnomalyHunter.ps1'
$Logs = 'logs'
$Results = 'results'

function ScheduleTask {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument Get-PathName
    $trigger = New-ScheduledTaskTrigger -Daily -At 12am
    $principal = New-ScheduledTaskPrincipal -GroupId "Users"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "Anomaly detection" -Action $action -Trigger $trigger -Principal $principal -Settings $settings
}

function DeleteTool () {
    Write-Host "[*] Starting the deletion..."


    Get-PathName -NameOfFile $Code
    Get-PathName -NameOfFile $Logs

    #uninstall logs folders, scheduled tasks
    Write-Host "[*] Removing "$(Get-PathName -NameOfFile $Logs)"..." -f Cyan
    Remove-Item (Get-PathName -NameOfFile $Logs) -Recurse -Include *.*
    Remove-Item (Get-PathName -NameOfFile $Logs)

    Write-Host "[*] Removing "$(Get-PathName -NameOfFile $Results)"..." -f Cyan
    Remove-Item (Get-PathName -NameOfFile $Results) -Recurse -Include *.*
    Remove-Item (Get-PathName -NameOfFile $Results)

    Unregister-ScheduledTask -TaskName "Anomaly detection" -Confirm:$false
}