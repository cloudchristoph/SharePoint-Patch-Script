 <#
    Updated for SharePoint Server 2016 by Trevor Seward (https://thesharepointfarm.com). Original 
    script provided by Russ Maxwell, available for SharePoint 2013 from 
    https://blogs.msdn.microsoft.com/russmax/2013/04/01/why-sharepoint-2013-cumulative-update-takes-5-hours-to-install/.

    This script supports both SharePoint 2013 as well as SharePoint Server 2016. SharePoint Server 2016 supports both the
    sts*.exe and wssloc*.exe in the same directory.
 
    Version: 1.0.1
    Release Date: 11/07/2016
    License: MIT (https://github.com/Nauplius/SharePoint-Patch-Script/blob/master/LICENSE)
 #>

Add-PSSnapin Microsoft.SharePoint.PowerShell -EA Stop

<#
    .SYNOPSIS
    Install-SPPatch
    .DESCRIPTION
    Install-SPPatch reduces the amount of time it takes to install SharePoint patches. This module supports SharePoint 2013 and SharePoint 2016. Additional information
        can be found at https://github.com/Nauplius.
    .PARAMETER Path
        The folder where the patch file(s) reside.
    .PARAMETER Pause
        Pauses the Search Service Application(s) prior to stopping the SharePoint Search Services.
    .PARAMETER Stop
        Stop the SharePoint Search Services without pausing the Search Service Application(s).
    .PARAMETER SilentInstall
        Silently installs the patches without user input. Not specifying this parameter will cause each patch to prompt to install.
    .PARAMETER Resume
        Resumes and Starts the Search Service Application and Services. Default is true.
    .EXAMPLE
        Install-SPPatch -Path C:\Updates -Pause -SilentInstall
    .NOTES
        Author: Trevor Seward
        Date: 10/14/2016
        https://thesharepointfarm.com
        https://github.com/Nauplius

#>

Function Install-SPPatch
{
    param
    (
        [string]
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        $Path,
        [switch]
        [Parameter(Mandatory=$true,ParameterSetName="PauseSearch")]
        $Pause,
        [switch]
        [Parameter(Mandatory=$true,ParameterSetName="StopSearch")]
        $Stop,
        [switch]
        [Parameter(Mandatory=$false)]
        $SilentInstall,
        [switch]
        [Parameter(Mandatory=$false)]
        $Resume = $true
    )

    $version = (Get-SPFarm).BuildVersion
    $majorVersion = $version.Major
    $startTime = Get-Date
    Write-Host -ForegroundColor Green "Current build: $version"
    ########################### 
    ##Ensure Patch is Present## 
    ###########################

    if($majorVersion -eq '16')
    {
        $sts = Get-ChildItem -LiteralPath $Path | where{$_.Name -match 'sts([A-Za-z0-9\-]+).exe'}
        $wssloc = Get-ChildItem -LiteralPath $Path | where{$_.Name -match 'wssloc([A-Za-z0-9\-]+).exe'}

        if($sts -eq $null -or $wssloc -eq $null)
        {
            Write-Host 'Missing the sts or wssloc patch. Please make sure both patches are present in the same directory.' -ForegroundColor Red
            return
        }

        $patchfiles = $sts, $wssloc
        Write-Host -for Yellow "Installing $sts and $wssloc"
    }
    elseif ($majorVersion -eq '15')
    {
        $patchfiles = Get-ChildItem -LiteralPath $Path | ?{$_.Extension -eq ".exe"}
        
        if($patchfiles -eq $null) 
        { 
            Write-Host 'Unable to retrieve the file(s).  Exiting Script' -ForegroundColor Red 
            return 
        }

        Write-Host -ForegroundColor Yellow "Installing $patchfiles"
    }

    ######################## 
    ##Stop Search Services## 
    ######################## 
    ##Checking Search services## 

    $oSearchSvc = Get-Service "OSearch$majorVersion" 
    $sPSearchHCSvc = Get-Service "SPSearchHostController"

    if(($oSearchSvc.status -eq 'Running') -or ($sPSearchHCSvc.status-eq 'Running')) 
    { 
        if($Pause) 
        { 
            $ssas = Get-SPEnterpriseSearchServiceApplication

            foreach($ssa in $ssas)
            {
                Write-Host -ForegroundColor Yellow "Pausing the Search Service Application: $($ssa.DisplayName)"
                Write-Host  -ForegroundColor Yellow  'This could take a few minutes...'
                $ssa.Pause() | Out-Null
            }
        }
        elseif($Stop) 
        { 
            Write-Host 'Continuing without pausing the Search Service Application'
        }
    }

    Write-Host -ForegroundColor Yellow 'Stopping Search Services if they are running'

    if($oSearchSvc.status -eq 'Running') 
    { 
        Set-Service -Name "OSearch$majorVersion" -StartupType Disabled 
        Stop-Service "OSearch$majorVersion" -WA 0
    }

    if($sPSearchHCSvc.status -eq 'Running') 
    { 
        Set-Service 'SPSearchHostController' -StartupType Disabled 
        Stop-Service 'SPSearchHostController' -WA 0
        $Stopped = 1
    }

    Write-Host -ForegroundColor Green 'Search Services are Stopped'
    Write-Host

    ####################### 
    ##Stop Other Services## 
    ####################### 
    Set-Service -Name 'IISADMIN' -StartupType Disabled 
    Set-Service -Name 'SPTimerV4' -StartupType Disabled

    Write-Host -ForegroundColor Yellow 'Gracefully stopping IIS...'
    Write-Host 
    iisreset -stop -noforce 
    Write-Host -ForegroundColor Yellow 'Stopping SPTimerV4'
    Write-Host

    $sPTimer = Get-Service 'SPTimerV4' 
    if($sPTimer.Status -eq 'Running') 
    {
        Stop-Service 'SPTimerV4'
    }

    Write-Host -ForegroundColor Green 'Services are Stopped'
    Write-Host 
    Write-Host

    ################## 
    ##Start patching## 
    ################## 
    Write-Host -ForegroundColor Yellow 'Working on it... Please keep this PowerShell window open...'
    Write-Host

    $patchStartTime = Get-Date

    foreach($patchfile in $patchfiles)
    {
        $filename = $patchfile.Basename

        if($SilentInstall)
        {
            $process = Start-Process $filename -ArgumentList '/passive /quiet' -PassThru -Wait
        }
        else 
        {
            $process = Start-Process $filename -ArgumentList '/norestart' -PassThru -Wait
        }

        if($process.ExitCode -eq '3010')
        {
            $reboot = $true
        }

        Write-Host -ForegroundColor Yellow "Patch $patchfile installed with Exit Code $($process.ExitCode)"
    }

    $patchEndTime = Get-Date

    Write-Host 
    Write-Host -ForegroundColor Yellow ('Patch installation completed in {0:g}' -f ($patchEndTime - $patchStartTime))
    Write-Host

    ################## 
    ##Start Services## 
    ################## 
    Write-Host -ForegroundColor Yellow 'Starting Services'
    Set-Service -Name 'SPTimerV4' -StartupType Automatic 
    Set-Service -Name 'IISADMIN' -StartupType Automatic

    ##Grabbing local server and starting services## 
    $server = Get-SPServer $ENV:COMPUTERNAME

    Start-Service 'SPTimerV4'
    Start-Service 'IISAdmin'

    ###Ensuring Search Services were stopped by script before Starting" 
    if($Stop -and ($Resume)) 
    { 
        Set-Service -Name "OSearch$majorVersion" -StartupType Automatic 
        Start-Service "OSearch$majorVersion"
        Set-Service 'SPSearchHostController' -StartupType Automatic 
        Start-Service 'SPSearchHostController'
    }
    else 
    {
        Write-Host -ForegroundColor Red "Not starting Search Services as `$Resume` is set to false."
    } 

    ###Resuming Search Service Application if paused### 
    if($Pause -and ($Resume)) 
    { 
        $ssas = Get-SPEnterpriseSearchServiceApplication

        foreach($ssa in $ssas)
        {
            Write-Host -ForegroundColor Yellow "Resuming the Search Service Application: $($ssa.DisplayName)"
            Write-Host -ForegroundColor Yellow 'This could take a few minutes...'
            $ssa.Resume() | Out-Null
        }
    }
    else 
    {
        Write-Host -ForegroundColor Red "Not resuming Search Service Application as `$Resume` is set to false."        
    }

    $endTime = Get-Date
    Write-Host -ForegroundColor Green 'Services are Started'
    Write-Host 
    Write-Host 
    Write-Host -ForegroundColor Yellow ('Script completed in {0:g}' -f ($endTime - $startTime))
    Write-Host -ForegroundColor Yellow 'Started:'  $startTime 
    Write-Host -ForegroundColor Yellow 'Finished:'  $endTime 

    if($reboot)
    {
        Write-Host -ForegroundColor Yellow 'A reboot is required'
    }
}
