@{
    RootModule        = 'WindowsBaseline.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f2b1c9de-4a77-4a6e-9f2a-6c1b0d8a7e31'
    Author            = 'Ziyad Uqdah'
    Description       = 'Audits and remediates a CIS-derived Windows Server security baseline. Controls are declared as data, so auditing and remediation cannot drift apart.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-BaselineControl',
        'Test-WindowsBaseline',
        'Set-WindowsBaseline',
        'New-BaselineReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Security', 'CIS', 'Baseline', 'WindowsServer', 'Hardening')
            ProjectUri = 'https://github.com/zuqdah/windows-baseline-automation'
        }
    }
}
