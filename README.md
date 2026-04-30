# Get-Anomalies-Powershell-based-tool

## Introduction


<p>This tool is based on Powershell script and requires Sysmon to work and analyze your logs.</p>
<p>Beforehand this you will need to install: </p>

- Sysmon (https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon)
- WinLogs-Toolkit (https://github.com/toktarbayevaaiymgul/WinLogs-Toolkit)

## Description
<p>AnomalyHunter is the tool to collect and analyze your logs using Sysmon, couting anomalies and writing down results of the execution in CSV files: <strong>"execHistory", "anomalyHistory", "resultHistory"</strong>. </p>

<p>For execution of this idea, had been developed functions,
such as:</p>

1. **Get-FileName** function is used to create the name of
the .csv file based on the input parameters (personalized
name depending on input EID, Properties)

2. **Get-ExecHistoryFileName** function is used to create a
name for “history” .csv file that will contain all logs from
previous runs and will be used and transferred inside
other functions

3. **Get-ResultHistoryFileName** function is used to create
a name for “results” .csv file that will contain results of
the last run for comparison purposes between “results”
(aka last run) and “history” to determine which events
had happened before

4. **Get-StartTime function** is used to determine time of event from which the
analysis should start from using if-else statement: if “history”.csv is created and
present, it uses the time of the event log where previous run ended on, or if there is
no “history”.csv, it finds oldest event log and writes down its time as a StartTime

5. 61-77 lines of code are used to determine StartTime and EndTime of the code-
run, ensuring all datetime objects are formatted to culture-invariant syntax

6. 96-104 lines of code are used to store events from StartTime to EndTime, group
them based on passed Properties (E.g. $Image & $ParentImage) and store them in
$eventsGrouped

7. **Compare-EventGrouped** function is used to compare $history.csv with
$eventsGrouped, declare properties for groups of the events (e.g. $minTime,
$maxTime, $eventCount, $keyName – contains properties like $Image,
$parentImage), creates $curGroupObj array to contain all of those properties +
$isAnomaly (set to $false by default)

8. **Get-PathName** to get the name of the path where the tool and all folders, files (CSVs) are.

9. **ScheduleTask** function is used to schedule a task that will be running everyday at 12am.

10. **DeleteTool** function is used to delete the tool and files execution had created.

By comparing each event from $history.csv (existing from previous executions
events) and $eventsGrouped (current events found in this specific run), function
determines if the specific event had ever existed before based on Properties declared
in $curGroupObj. If existed – it is non-anomaly, if not – it is anomaly

Architecture:
<img width="1421" height="965" alt="image" src="https://github.com/user-attachments/assets/49906706-0063-4fce-bb2a-dde27454cbe1" />

# Installation proccess
<p>Make sure that WinLogs-Toolkit is in the same directory as Invoke-AnomalyHunter.</p>

`Import-Module ./Invoke-AnomalyHunter.ps1`

- To run it once:
`Invoke-AllAnomalyHunter`

- To schedule it for continuous scheduled execution:
`Add-ScheduledAnomalyHunter`

- To delete the scheduled task:
`Remove-ScheduledAnomalyHunter`

- To delete the tool:
`Uninstall-AnomalyHunter`
