# SharePoint Patch Script
An updated version of Russ Maxwell's "5 hour" SharePoint Patch Script supporting SharePoint 2013 and SharePoint 2016. Original created for SharePoint 2013 by Russ Maxwell, this script has been updated with a few new features:

* Support for SharePoint 2016 and SharePoint 2013 in the same script
* Support for multiple patch files for both platforms
* Support for pausing/stopping multiple SharePoint Search Service Applications
* It's now a module with a cmdlet of Install-SPPatch.

Upcoming features include:

* Disable resuming of Search (this would be useful in patching multiple SharePoint servers)
* Better information on what the script is doing

Usage:

`Import-Module .\SharePointPatchScript.psm1`
* You can also drop the psm1 file in your modules directory, by default it is located at `C:\Users\<username>\Documents\WindowsPowerShell\Modules`

Example:

`Install-SPPatch -Path C:\Patches -Pause -SilentInstall`

Switch reference:
* `-Path` is an absolute path to the folder location of the patches
* `-SilentInstall` includes the arguments `/passive /quiet`. This prevents any of the patch UI from appearing (useful to patch as quickly as possible without user intervention)
* `-Pause` pauses the Search Service Application(s) prior to stopping the Search Services.
* `-Stop` simply stops the Search Services without pausing the Search Service Application.

`-Pause` and `-Stop` are mutually exclusive.

Russ Maxwell's original script is available at https://blogs.msdn.microsoft.com/russmax/2013/04/01/why-sharepoint-2013-cumulative-update-takes-5-hours-to-install/.
