# Configure-Server.ps1
# Server hardening script
# Bob 3/2019 - updated 11/2021 jm - added LLMNR per audit finding
# DO NOT RUN ON DC01 - breaks the old line-of-business app
#
# This is the "before": a real-shaped legacy script, kept so the refactor has
# something to be measured against. Everything wrong with it is deliberate.

Write-Host "Starting server hardening..." -ForegroundColor Green

# disable smb1
Write-Host "Disabling SMB1"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "SMB1" -Value 0

# RDP NLA
Write-Host "Setting NLA"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1

# script block logging - security asked for this
Write-Host "Script block logging"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1

# LLMNR off
Write-Host "LLMNR"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0

# ntlm
Write-Host "NTLM"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5

# installer elevated - CVE thing from 2020
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -Value 0

Write-Host "Done!" -ForegroundColor Green
Write-Host "Remember to reboot" -ForegroundColor Yellow

# TODO: add the file server settings from the other script
# TODO: someone should check if the 2016 boxes need the same thing
# TODO: this fails on some servers, not sure why, just rerun it
