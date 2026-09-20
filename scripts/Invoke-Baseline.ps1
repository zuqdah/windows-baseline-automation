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
    $changes = $null

    switch ($Mode) {
        'Audit' {
            $report = Test-WindowsBaseline | New-BaselineReport
        }
        'WhatIf' {
            $changes = @(Set-WindowsBaseline -WhatIf)
            $report = Test-WindowsBaseline | New-BaselineReport
        }
        'Remediate' {
            $changes = @(Set-WindowsBaseline -Confirm:$false)
            # Re-audit afterwards: the proof is the state, not the return value.
            $report = Test-WindowsBaseline | New-BaselineReport
        }
    }

    # Azure Run Command caps its message at about 4 KB and truncates from the
    # front, so an oversized payload silently loses its opening brace and stops
    # being JSON at all. Only measurements travel. Each control's name,
    # description, and CIS reference are static text that already lives in the
    # module and the README, and sending them on every run is what overran the
    # cap: the audit fit at 3.6 KB and -WhatIf, which adds the change list, did
    # not.
    $wire = [ordered]@{ mode = $Mode }

    if ($null -ne $changes) {
        $wire.changes = @(
            foreach ($c in $changes) {
                [ordered]@{
                    Id       = $c.Id
                    Action   = $c.Action
                    Previous = $c.Previous
                    Applied  = $c.Applied
                    Reason   = $c.Reason
                }
            }
        )
    }

    $wire.report = [ordered]@{
        GeneratedAt   = $report.GeneratedAt
        ComputerName  = $report.ComputerName
        Total         = $report.Total
        Compliant     = $report.Compliant
        NonCompliant  = $report.NonCompliant
        HighSeverity  = $report.HighSeverity
        CompliantRate = $report.CompliantRate
        Failing       = @(
            foreach ($f in $report.Failing) {
                [ordered]@{
                    Id       = $f.Id
                    Severity = $f.Severity
                    Expected = $f.Expected
                    Actual   = $f.Actual
                }
            }
        )
    }

    $json = [pscustomobject]$wire | ConvertTo-Json -Depth 8 -Compress

    # Fail loudly here rather than letting the agent hand back a truncated
    # document that only looks like a parse error further down the pipeline.
    if ($json.Length -gt 3500) {
        throw "Report is $($json.Length) bytes and will be truncated by Run Command."
    }

    # One JSON document between markers, so the pipeline can find it among
    # whatever else the agent prints.
    Write-Output '---BASELINE-JSON-START---'
    Write-Output $json
    Write-Output '---BASELINE-JSON-END---'
}
