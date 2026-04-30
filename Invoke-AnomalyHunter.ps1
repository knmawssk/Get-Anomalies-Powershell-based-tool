Import-Module ./Format-WinEvent.ps1

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
 
    $fileName = 'resultHistory_' + (Get-FileName -LogName $LogName -EID $EID -Properties $Properties)
    $fileDir = 'results'
    if (-not(Test-Path -Path $fileDir))
    {
        New-Item -ItemType Directory -Name $fileDir | Out-Null
    }
    
    return (Join-Path $fileDir $fileName)
}

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

    $execHistoryFilePath = Get-ExecHistoryFileName -LogName $LogName -EID $EID -Properties $Properties

    Write-Host "[*] [Get-StartTime] `$execHistoryFilePath=" -NoNewline -ForegroundColor cyan
    Write-Host $execHistoryFilePath -ForegroundColor yellow


    if ((Test-Path $execHistoryFilePath) -eq $True)  
    { 

        $startTime = (Import-Csv $execHistoryFilePath | Sort-Object endTime -Descending | Select-Object -First 1).endTime
        $startTime = ConvertFrom-DateTimeFormatted -DateTime $startTime

    }
    else
    {
        $oldestEventTime = (Get-WinEvent -Oldest -MaxEvents 1 -FilterHashtable @{LogName = $LogName; Id = $EID} | Select-Object TimeCreated | Select-Object -First 1).TimeCreated
        
        Write-Host "OldestEventTime is $($oldestEventTime)" -ForegroundColor Magenta
        
        $startTime = ConvertFrom-DateTimeFormatted -DateTime $oldestEventTime


    }

    return $startTime
}

function Get-MaxEndTime ([String] $LogName, [Int] $EID, [String[]] $Properties)
{
    # By default Get-WinEvent returns events newest to oldest.
    $newestEventTime = (Get-WinEvent -MaxEvents 1 -FilterHashtable @{LogName = $LogName; Id = $EID} | Select-Object TimeCreated | Select-Object -First 1).TimeCreated
    
    Write-Host "NewestEventTime is $($newestEventTime)" -ForegroundColor Magenta

    $maxEndTime = ConvertFrom-DateTimeFormatted -DateTime $newestEventTime

    return $maxEndTime
}




function Invoke-AnomalyHunter ([String] $LogName, [Int] $EID, [String[]] $Properties, [DateTime] $StartTime, [DateTime] $EndTime) 
{
    # Ensuring all datetime objects are formatted to culture-invariant syntax for consistent retrieval from $configFile.

    $executionTimeFormatted = ConvertTo-DateTimeFormatted -DateTime (Get-Date)
    $startTimeFormatted = ConvertTo-DateTimeFormatted -DateTime $StartTime
    $endTimeFormatted = ConvertTo-DateTimeFormatted -DateTime $EndTime

    # STEP 3: Querying event logs for current grouping.

    Write-Host "[*] Using Get-WinEvent to query from $startTimeFormatted to $endTimeFormatted" -f cyan
    $events = (Get-WinEvent -FilterHashtable @{LogName = $LogName; Id = $EID ; startTime = $StartTime; endTime = $EndTime} -errorAction SilentlyContinue)

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

$global:comparisonResultArr = $comparisonResultArr

    Write-Host "[*] STARTING call Compare-EventGrouped..." -f yellow
    $comparisonResultArr = Compare-EventGrouped -EventsGrouped $eventsGrouped -EventGroupedHistory $eventGroupedHistory
    Write-Host "[*] FINISHING call Compare-EventGrouped...`$comparisonResultArr.Count=$($comparisonResultArr.Count)" -f yellow
    $anomalyArr = $comparisonResultArr | Where-Object {$_.isAnomaly -eq $True}
    $anomalyCount = ($comparisonResultArr | Where-Object {$_.isAnomaly -eq $True}).Count 
    $nonAnomalyCount = $eventsGrouped.Count - $anomalyArr.Count 
    Write-Host "[*] Anomaly Count is $anomalyCount" 
    Write-Host "[*] Non anomaly Count is $nonAnomalyCount" 
    Write-Host "[*] $anomalyCount + $nonAnomalyCount = $($eventsGrouped.Count) ??? $(($anomalyCount + $nonAnomalyCount) -eq $eventsGrouped.Count)" -f cyan


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

        minTime = $minTime
        maxTime = $maxTime
        
        eventCount = $events.Count
        eventGroupedCount = $eventsGrouped.Count
    }

    $execHistoryFilePath = Get-ExecHistoryFileName -LogName $LogName -EID $EID -Properties $Properties
    $execHistoryObj | Export-Csv -Path $execHistoryFilePath -Append
    Write-Host "[*] Exported `$execHistoryFilePath=$execHistoryFilePath"

    
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

    }
}

# function Compare-EventGrouped ([String] $LogName, [Int] $EID, [String[]] $Properties)
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

    #loop for retrieving events
    for ($i=0; $i -lt $EventsGrouped.Count; $i++)
    {
        $curGroup = $EventsGrouped[$i]


        $timeBounds = $curGroup.Group | Select-Object Image, UtcTime | Measure-Object -Minimum -Maximum -Property UtcTime
        $minTime = $timeBounds.Minimum
        $maxTime = $timeBounds.Maximum
        $eventCount = $curGroup.Count
        $keyName = $curGroup.Name # this is the single string of the $Properties used in Group-Object outside this function

        Write-Host "[*] From time $minTime to $maxTime, there were $eventCount occurrences of keyName=$keyName" -f cyan
        
        $curGroupObj = [PSCustomObject] @{
            # Add boolean property to easily label if current grouping is an anomaly (default to $false).
            isAnomaly = $false
            minTime = $minTime
            maxTime = $maxTime
            eventCount = $eventCount
            key = $keyName
        }

        #comparing new ver with old one
        # Look for history objects that have the same key ($Properties as a single string) as our current grouped events.
        $curGroupHistoryObj = $EventGroupedHistory | Where-Object { $_.key -eq $keyName } | Select-Object -First 1

        if ($curGroupHistoryObj -ne $null)
        {

            $matchedEventCount=$matchedEventCount+1

            #storing it in array for comparison purposes
            $nonanomalycomparison = [PSCustomObject] @{
                #adding those to compare old and new
                minTime_oldfile = $curGroupHistoryObj.minTime
                minTime_newfile = $curGroupObj.minTime
                maxTime_oldfile = $curGroupHistoryObj.maxTime
                maxTime_newfile = $curGroupObj.maxTime
                eventCount_oldfile = $curGroupHistoryObj.eventCount
                eventCount_newfile = $curGroupObj.eventCount

                parentimage = $curGroupObj.parentImage #check here
                image = $curGroupObj.Image
            }

            $nonAnomalyComparisonHistory += $nonanomalycomparison #change

            # Update current grouping history object with statistics from current grouping.
            $curGroupHistoryObj | Add-Member -MemberType NoteProperty -Name 'isAnomaly' -Value $false
            $curGroupHistoryObj.minTime = @($curGroupHistoryObj.minTime, $curGroupObj.minTime) | Sort-Object | Select-Object -First 1
            $curGroupHistoryObj.maxTime = @($curGroupHistoryObj.maxTime, $curGroupObj.maxTime) | Sort-Object | Select-Object -Last 1
            $curGroupHistoryObj.eventCount = $curGroupObj.eventCount + $curGroupHistoryObj.eventCount
        }
        else
        {
            # If current grouping is NEW then update boolean flag to an anomaly.
            $curGroupObj.isAnomaly = $true

            $EventGroupedHistory += $curGroupObj #just adding to usual file
            $anomalyCount = $anomalyCount+1 #summing to get the number of anomalies

        }
        #$eventsGroupedObjArr += $curGroupObj
    }

    Write-Host "Number of anomalies detected is $anomalyCount"
    Write-Host "Number of 'normal' events is $matchedEventCount" 

    return $EventGroupedHistory
}




function Invoke-AllAnomalyHunter{
    @([PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('ParentImage', 'Image')},[PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('User','Image','CommandLine')}, [PSCustomObject] @{LogName = 'Microsoft-Windows-Sysmon/Operational'; EID = 1; Properties = @('User','Image')} ) | ConvertTo-Json | Set-Content config.json
    $configJson = Get-Content -Path config.json | ConvertFrom-Json 
    foreach ($config in $configJson) 
    { 
        # STEP 1: Extract properties for grouping from current config. 
        $logName = $config.LogName 
        $eid = $config.EID 
        $properties = $config.properties

    # STEP 2: Retrieve start/end times for querying event logs for current grouping.

    # Define bin size for frequency.
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

$script:taskName = "Anomaly detection"

function Add-ScheduledAnomalyHunter { 
    $action = New-ScheduledTaskAction -WorkingDirectory ($PSCommandPath -replace '[^\\/]+$','') -Execute "powershell.exe " -Argument "-ExecutionPolicy Bypass -Command `"import-module './Invoke-AnomalyHunter.ps1'; Invoke-AllAnomalyHunter; write-host 'Ending!'; start-sleep 2`"" 
    $firstTaskRunTime = (Get-Date).AddMinutes(2) # first run is 2 minutes from now 
    $trigger = New-ScheduledTaskTrigger -Daily -At $firstTaskRunTime 
 
    $principal = New-ScheduledTaskPrincipal -GroupId "Users" 
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest 
    Register-ScheduledTask -TaskName $script:taskName -Action $action -Trigger $trigger -Principal $principal 
}

function Remove-ScheduledAnomalyHunter {
    Unregister-ScheduledTask -TaskName $script:taskName -Confirm:$false
}

function Uninstall-AnomalyHunter () {
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

    Remove-ScheduledAnomalyHunter
}