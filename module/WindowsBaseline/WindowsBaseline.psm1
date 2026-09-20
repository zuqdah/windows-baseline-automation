<#
    WindowsBaseline

    The security baseline as data, not as a list of commands. Each control
    declares what it expects; auditing and remediation are the same
    definitions read two different ways, so they cannot drift apart.

    Every registry access goes through one pair of functions, which keeps the
    controls declarative and makes the whole module testable without touching
    a real machine.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Controls = @(
    @{
        Id          = 'SMB1-Disabled'
        Name        = 'SMBv1 server disabled'
        Description = 'SMBv1 is unauthenticated, unencrypted, and the transport used by WannaCry and NotPetya.'
        Severity    = 'High'
        Path        = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        ValueName   = 'SMB1'
        Expected    = 0
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 18.4.3'
    }
    @{
        Id          = 'RDP-NLA-Required'
        Name        = 'RDP requires Network Level Authentication'
        Description = 'Without NLA, a session is established before the user authenticates, which exposes the logon surface to unauthenticated callers.'
        Severity    = 'High'
        Path        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        ValueName   = 'UserAuthentication'
        Expected    = 1
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 18.10.57.3.9.4'
    }
    @{
        Id          = 'PowerShell-ScriptBlock-Logging'
        Name        = 'PowerShell script block logging enabled'
        Description = 'Records the script content PowerShell actually executes, including code assembled at runtime. Without it, an incident has little to read.'
        Severity    = 'Medium'
        Path        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
        ValueName   = 'EnableScriptBlockLogging'
        Expected    = 1
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 18.10.87.2.1'
    }
    @{
        Id          = 'LLMNR-Disabled'
        Name        = 'LLMNR disabled'
        Description = 'LLMNR broadcasts name lookups to the local network, which is what responder-style credential capture relies on.'
        Severity    = 'Medium'
        Path        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
        ValueName   = 'EnableMulticast'
        Expected    = 0
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 18.6.4.2'
    }
    @{
        Id          = 'NTLMv2-Only'
        Name        = 'LAN Manager authentication level set to NTLMv2 only'
        Description = 'Refuses LM and NTLMv1 responses, which are trivially crackable when captured.'
        Severity    = 'High'
        Path        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
        ValueName   = 'LmCompatibilityLevel'
        Expected    = 5
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 2.3.11.7'
    }
    @{
        Id          = 'Installer-Not-Elevated'
        Name        = 'Windows Installer always-elevated disabled'
        Description = 'AlwaysInstallElevated lets any user install a package as SYSTEM, which is a direct privilege escalation path.'
        Severity    = 'High'
        Path        = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer'
        ValueName   = 'AlwaysInstallElevated'
        Expected    = 0
        Kind        = 'DWord'
        Reference   = 'CIS Microsoft Windows Server 2025 Benchmark, 18.10.14.1'
    }
)

function Get-RegistryValue {
    <#
        .SYNOPSIS
            Reads a registry value, returning $null when the key or value is absent.
        .DESCRIPTION
            A missing value is a legitimate state for a baseline check, not an
            error, so this never throws for absence. It is also the single
            seam the tests mock.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    } catch {
        return $null
    }

    $value = $key.GetValue($Name, $null)
    return $value
}

function Set-RegistryValue {
    <#
        .SYNOPSIS
            Writes a registry value, creating the key path when it does not exist.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [ValidateSet('DWord', 'String', 'QWord')][string]$Kind = 'DWord'
    )

    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}

function Get-BaselineControl {
    <#
        .SYNOPSIS
            Returns the baseline's control definitions.
        .PARAMETER Id
            One or more control IDs. Omit to return every control.
        .EXAMPLE
            Get-BaselineControl | Format-Table Id, Severity, Name
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Id
    )

    $selected = if ($PSBoundParameters.ContainsKey('Id')) {
        foreach ($wanted in $Id) {
            $match = $script:Controls | Where-Object { $_.Id -eq $wanted }
            if (-not $match) {
                throw "No control with Id '$wanted'. Known controls: $(($script:Controls.Id) -join ', ')"
            }
            $match
        }
    } else {
        $script:Controls
    }

    foreach ($control in $selected) {
        [pscustomobject]$control
    }
}

function Test-WindowsBaseline {
    <#
        .SYNOPSIS
            Audits the machine against the baseline. Changes nothing.
        .DESCRIPTION
            Returns one result per control, including the value actually found,
            so a drift report says what is wrong rather than only that
            something is.
        .PARAMETER Id
            One or more control IDs. Omit to audit every control.
        .EXAMPLE
            Test-WindowsBaseline | Where-Object { -not $_.Compliant }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Id
    )

    # Forward only the selection, never the caller's common parameters.
    $selection = @{}
    if ($PSBoundParameters.ContainsKey('Id')) { $selection['Id'] = $Id }

    foreach ($control in (Get-BaselineControl @selection)) {
        $actual = Get-RegistryValue -Path $control.Path -Name $control.ValueName

        [pscustomobject]@{
            Id          = $control.Id
            Name        = $control.Name
            Severity    = $control.Severity
            Path        = $control.Path
            ValueName   = $control.ValueName
            Expected    = $control.Expected
            Actual      = $actual
            Compliant   = ($null -ne $actual) -and ([int]$actual -eq [int]$control.Expected)
            Reference   = $control.Reference
            Description = $control.Description
        }
    }
}

function Set-WindowsBaseline {
    <#
        .SYNOPSIS
            Brings the machine into line with the baseline.
        .DESCRIPTION
            Only non-compliant controls are written, so a second run makes no
            changes. Supports -WhatIf, which reports what would change without
            touching anything.
        .PARAMETER Id
            One or more control IDs. Omit to remediate every control.
        .EXAMPLE
            Set-WindowsBaseline -WhatIf
        .EXAMPLE
            Set-WindowsBaseline -Id SMB1-Disabled
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Id
    )

    # -WhatIf and -Confirm belong to this function; the audit takes neither.
    $selection = @{}
    if ($PSBoundParameters.ContainsKey('Id')) { $selection['Id'] = $Id }

    foreach ($result in (Test-WindowsBaseline @selection)) {
        if ($result.Compliant) {
            [pscustomobject]@{
                Id       = $result.Id
                Name     = $result.Name
                Action   = 'None'
                Previous = $result.Actual
                Applied  = $result.Expected
                Reason   = 'already compliant'
            }
            continue
        }

        $changed = $false
        if ($PSCmdlet.ShouldProcess("$($result.Path)\$($result.ValueName)", "set to $($result.Expected) for $($result.Id)")) {
            $control = Get-BaselineControl -Id $result.Id
            Set-RegistryValue -Path $control.Path -Name $control.ValueName -Value $control.Expected -Kind $control.Kind -Confirm:$false
            $changed = $true
        }

        [pscustomobject]@{
            Id       = $result.Id
            Name     = $result.Name
            Action   = if ($changed) { 'Remediated' } else { 'WouldRemediate' }
            Previous = $result.Actual
            Applied  = $result.Expected
            Reason   = if ($null -eq $result.Actual) { 'value not set' } else { "found $($result.Actual)" }
        }
    }
}

function New-BaselineReport {
    <#
        .SYNOPSIS
            Summarizes audit results into a report suitable for a pipeline artifact.
        .PARAMETER Result
            Output from Test-WindowsBaseline.
        .EXAMPLE
            Test-WindowsBaseline | New-BaselineReport | ConvertTo-Json -Depth 5
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject[]]$Result
    )

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $Result) { $all.Add($item) } }
    end {
        $failing = @($all | Where-Object { -not $_.Compliant })
        [pscustomobject]@{
            GeneratedAt   = (Get-Date).ToUniversalTime().ToString('o')
            ComputerName  = $env:COMPUTERNAME
            Total         = $all.Count
            Compliant     = $all.Count - $failing.Count
            NonCompliant  = $failing.Count
            HighSeverity  = @($failing | Where-Object { $_.Severity -eq 'High' }).Count
            CompliantRate = if ($all.Count) { [math]::Round(100 * ($all.Count - $failing.Count) / $all.Count, 1) } else { 0 }
            Failing       = @($failing | Select-Object Id, Severity, Expected, Actual, Reference)
            Results       = @($all)
        }
    }
}

Export-ModuleMember -Function Get-BaselineControl, Test-WindowsBaseline, Set-WindowsBaseline, New-BaselineReport
