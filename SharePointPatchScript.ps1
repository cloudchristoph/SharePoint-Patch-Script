 <#
    Updated for SharePoint Server 2016 by Trevor Seward (https://thesharepointfarm.com). Original 
    script provided by Russ Maxwell, available for SharePoint 2013 from 
    https://blogs.msdn.microsoft.com/russmax/2013/04/01/why-sharepoint-2013-cumulative-update-takes-5-hours-to-install/.

    This script handles both SharePoint 2013 as well as SharePoint Server 2016. SharePoint Server 2016 supports both the
    sts*.exe and wssloc*.exe in the same directory.
 
    Version: 1.0
    Release Date: 10/06/2016
    License: MIT (https://github.com/tseward/SharePoint-Patch-Script/blob/master/LICENSE)
 #>

Add-PSSnapin Microsoft.SharePoint.PowerShell -EA 0


$version = (Get-SPFarm).BuildVersion.Major


########################### 
##Ensure Patch is Present## 
###########################

if($version -eq '16')
{
    $sts = Get-ChildItem | where{$_.Name -match 'sts([A-Za-z0-9\-]+).exe'}
    $wssloc = Get-ChildItem | where{$_.Name -match 'wssloc([A-Za-z0-9\-]+).exe'}


    if($sts -eq $null -or $wssloc -eq $null)
    {
        Write-Host 'Missing the sts or wssloc patch. Please make sure both patches are present in the same directory.' -ForegroundColor Red
        Return
    }

    $patchfiles = $sts, $wssloc
    Write-Host -for Yellow "Installing $sts and $wssloc"
}
elseif ($version -eq '15')
{
    $patchfiles = Get-ChildItem | ?{$_.Extension -eq ".exe"}
    
    if($patchfiles -eq $null) 
    { 
      Write-Host "Unable to retrieve the file(s).  Exiting Script" -ForegroundColor Red 
      Return 
    }

    Write-Host -ForegroundColor Yellow "Installing $patchfiles"
}



######################## 
##Stop Search Services## 
######################## 
##Checking Search services## 
$srchctr = 1 
$srch4srvctr = 1 
$srch5srvctr = 1

$srv4 = get-service "OSearch$version" 
$srv5 = get-service "SPSearchHostController"

If(($srv4.status -eq "Running") -or ($srv5.status-eq "Running")) 
  { 
    Write-Host "Choose 1 to Pause Search Service Application" -ForegroundColor Cyan 
    Write-Host "Choose 2 to leave Search Service Application running" -ForegroundColor Cyan 
    $searchappresult = Read-Host "Press 1 or 2 and hit enter"  
    Write-Host 
   

   if($searchappresult -eq 1) 
    { 
        $ssas = Get-SPEnterpriseSearchServiceApplication

        foreach($ssa in $ssas)
        {
            $srchctr = 2 
            Write-Host "Pausing the Search Service Application: $($ssa.DisplayName)" -foregroundcolor yellow 
            Write-Host 'This could take a few minutes...' -ForegroundColor Yellow 
            $ssa.pause()
        }
    } 
   

    elseif($searchappresult -eq 2) 
    { 
        Write-Host 'Continuing without pausing the Search Service Application'
    } 
    else 
    { 
        Write-Host "Run the script again and choose option 1 or 2" -ForegroundColor Red 
        Write-Host "Exiting Script" -ForegroundColor Red 
        Return 
    } 
  }

Write-Host 'Stopping Search Services if they are running' -foregroundcolor yellow 
if($srv4.status -eq "Running") 
  { 
    $srch4srvctr = 2 
    set-service -Name "OSearch$version" -startuptype Disabled 
    Stop-Service "OSearch$version"
  }

if($srv5.status -eq "Running") 
  { 
    $srch5srvctr = 2 
    Set-service "SPSearchHostController" -startuptype Disabled 
    Stop-Service 'SPSearchHostController'
  }

do 
  { 
    $srv6 = get-service "SPSearchHostController" 
    if($srv6.status -eq "Stopped") 
    { 
        $yes = 1 
    } 
    Start-Sleep -seconds 10 
  } 
  until ($yes -eq 1)

Write-Host 'Search Services are stopped' -foregroundcolor Green 
Write-Host

 

####################### 
##Stop Other Services## 
####################### 
Set-Service -Name "IISADMIN" -startuptype Disabled 
Set-Service -Name "SPTimerV4" -startuptype Disabled 
Write-Host "Gracefully stopping IIS W3WP Processes" -foregroundcolor yellow 
Write-Host 
iisreset -stop -noforce 
Write-Host "Stopping Services" -foregroundcolor yellow 
Write-Host

$srv2 = get-service "SPTimerV4" 
  if($srv2.status -eq "Running") 
  {Stop-Service "SPTimerV4"}

Write-Host "Services are Stopped" -ForegroundColor Green 
Write-Host 
Write-Host

################## 
##Start patching## 
################## 
Write-Host "Patching now keep this PowerShell window open" -ForegroundColor Magenta 
Write-Host 
$starttime = Get-Date

foreach($patchfile in $patchfiles)
{
    $filename = $patchfile.Basename 
    Start-Process $filename -ArgumentList "/passive /quiet"

    Start-Sleep -seconds 20 
    $proc = get-process $filename 
    $proc.WaitForExit()

    if($proc.ExitCode -eq '3010')
    {
        $rebootrequired = $true
    }

    Write-Host -ForegroundColor Yellow "Patch $patchfile installed with Exit Code $($proc.ExitCode)"
}

$finishtime = get-date 
Write-Host 
Write-Host "Patch installation complete" -foregroundcolor green 
Write-Host

 

################## 
##Start Services## 
################## 
Write-Host "Starting Services Backup" -foregroundcolor yellow 
Set-Service -Name "SPTimerV4" -startuptype Automatic 
Set-Service -Name "IISADMIN" -startuptype Automatic

##Grabbing local server and starting services## 
$servername = hostname 
$server = get-spserver $servername

Start-Service 'SPTimerV4'
Start-Service 'IISAdmin'


###Ensuring Search Services were stopped by script before Starting" 
if($srch4srvctr -eq 2) 
{ 
    set-service -Name "OSearch$version" -startuptype Automatic 
    Start-Service "OSearch$version"
} 
if($srch5srvctr -eq 2) 
{ 
    Set-service "SPSearchHostController" -startuptype Automatic 
    Start-Service 'SPSearchHostController'
}

###Resuming Search Service Application if paused### 
if($srchctr -eq 2) 
{ 
    $ssas = Get-SPEnterpriseSearchServiceApplication

    foreach($ssa in $ssas)
    {
        Write-Host "Resuming the Search Service Application: $($ssa.DisplayName)" -foregroundcolor yellow 
        Write-Host 'This could take a few minutes...' -ForegroundColor Yellow 
        $ssa.resume() 
    }
}

Write-Host "Services are Started" -foregroundcolor green 
Write-Host 
Write-Host 
Write-Host "Script Duration" -foregroundcolor yellow 
Write-Host "Started: " $starttime -foregroundcolor yellow 
Write-Host "Finished: " $finishtime -foregroundcolor yellow 

if($rebootrequired -eq $true)
{
    Write-Host -ForegroundColor Yellow 'A reboot is required'
}

Write-Host "Script Complete" 
