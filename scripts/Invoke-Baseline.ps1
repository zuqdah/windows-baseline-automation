<#
    The entry point the pipeline runs on the VM.

    This file defines a function and nothing else. Build-Bundle.ps1 appends
    the module, this function, and a single call to it, which keeps the
    bundle a valid script: a param block is only legal at the top of a file.
#>

function Invoke-Baseline {
    <#
        .SYNOPSIS
            Runs the baseline on this machine and prints a JSON report.
        .PARAMETER Mode
            Audit reports drift and changes nothing. Remediate applies the
            baseline. WhatIf reports what remediation would change.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Audit', 'Remediate', 'WhatIf')]
        [string]$Mode = 'Audit'
    )

    $ErrorActionPreference = 'Stop'
    $output = [ordered]@{ mode = $Mode }

    switch ($Mode) {
        'Audit' {
            $output.report = Test-WindowsBaseline | New-BaselineReport
        }
        'WhatIf' {
            $output.changes = @(Set-WindowsBaseline -WhatIf)
            $output.report = Test-WindowsBaseline | New-BaselineReport
        }
        'Remediate' {
            $output.changes = @(Set-WindowsBaseline -Confirm:$false)
            # Re-audit afterwards: the proof is the state, not the return value.
            $output.report = Test-WindowsBaseline | New-BaselineReport
        }
    }

    # One JSON document between markers, so the pipeline can find it among
    # whatever else the agent prints.
    Write-Output '---BASELINE-JSON-START---'
    Write-Output ([pscustomobject]$output | ConvertTo-Json -Depth 8 -Compress)
    Write-Output '---BASELINE-JSON-END---'
}
