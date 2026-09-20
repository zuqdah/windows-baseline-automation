<#
    The baseline's tests. Every registry read and write is mocked, so these
    run on any machine and never touch a real system.
#>

BeforeAll {
    $module = Join-Path $PSScriptRoot '..' 'module' 'WindowsBaseline' 'WindowsBaseline.psm1'
    Import-Module $module -Force
    $script:ModuleName = 'WindowsBaseline'
}

Describe 'Get-BaselineControl' {
    It 'returns every control by default' {
        $controls = Get-BaselineControl
        $controls.Count | Should -BeGreaterThan 0
        $controls.Id | Should -Contain 'SMB1-Disabled'
    }

    It 'gives each control the fields a report needs' {
        foreach ($control in Get-BaselineControl) {
            $control.Id          | Should -Not -BeNullOrEmpty
            $control.Name        | Should -Not -BeNullOrEmpty
            $control.Description | Should -Not -BeNullOrEmpty
            $control.Reference   | Should -Match 'CIS'
            $control.Severity    | Should -BeIn @('High', 'Medium', 'Low')
        }
    }

    It 'returns only what was asked for' {
        (Get-BaselineControl -Id 'SMB1-Disabled').Id | Should -Be 'SMB1-Disabled'
    }

    It 'fails loudly on an unknown control instead of silently doing nothing' {
        { Get-BaselineControl -Id 'Not-A-Control' } | Should -Throw '*No control with Id*'
    }
}

Describe 'Test-WindowsBaseline' {
    It 'reports a control as compliant when the value matches' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 0 }

        $result = Test-WindowsBaseline -Id 'SMB1-Disabled'

        $result.Compliant | Should -BeTrue
        $result.Actual    | Should -Be 0
        $result.Expected  | Should -Be 0
    }

    It 'reports the value it actually found when the machine has drifted' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 1 }

        $result = Test-WindowsBaseline -Id 'SMB1-Disabled'

        $result.Compliant | Should -BeFalse
        $result.Actual    | Should -Be 1
    }

    It 'treats a missing value as non-compliant rather than erroring' {
        Mock -ModuleName $ModuleName Get-RegistryValue { $null }

        $result = Test-WindowsBaseline -Id 'RDP-NLA-Required'

        $result.Compliant | Should -BeFalse
        $result.Actual    | Should -BeNullOrEmpty
    }

    It 'changes nothing' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 1 }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        Test-WindowsBaseline | Out-Null

        Should -Invoke -ModuleName $ModuleName Set-RegistryValue -Times 0
    }

    It 'audits every control when none is named' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 0 }

        (Test-WindowsBaseline).Count | Should -Be (Get-BaselineControl).Count
    }
}

Describe 'Set-WindowsBaseline' {
    It 'writes the expected value for a control that has drifted' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 1 }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        $result = Set-WindowsBaseline -Id 'SMB1-Disabled' -Confirm:$false

        $result.Action   | Should -Be 'Remediated'
        $result.Previous | Should -Be 1
        $result.Applied  | Should -Be 0
        Should -Invoke -ModuleName $ModuleName Set-RegistryValue -Times 1 -ParameterFilter {
            $Name -eq 'SMB1' -and $Value -eq 0
        }
    }

    It 'is idempotent: a compliant control is left alone' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 0 }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        $result = Set-WindowsBaseline -Id 'SMB1-Disabled' -Confirm:$false

        $result.Action | Should -Be 'None'
        Should -Invoke -ModuleName $ModuleName Set-RegistryValue -Times 0
    }

    It 'writes nothing under -WhatIf but still reports what would change' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 1 }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        $result = Set-WindowsBaseline -Id 'SMB1-Disabled' -WhatIf

        $result.Action | Should -Be 'WouldRemediate'
        Should -Invoke -ModuleName $ModuleName Set-RegistryValue -Times 0
    }

    It 'remediates only the controls that need it' {
        # Script block logging is off; everything else already matches.
        Mock -ModuleName $ModuleName Get-RegistryValue {
            param($Path, $Name)
            switch ($Name) {
                'EnableScriptBlockLogging' { 0 }
                'UserAuthentication'       { 1 }
                'LmCompatibilityLevel'     { 5 }
                default                    { 0 }
            }
        }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        $result = Set-WindowsBaseline -Confirm:$false

        @($result | Where-Object Action -eq 'Remediated').Id | Should -Be 'PowerShell-ScriptBlock-Logging'
        Should -Invoke -ModuleName $ModuleName Set-RegistryValue -Times 1
    }

    It 'explains why it acted' {
        Mock -ModuleName $ModuleName Get-RegistryValue { $null }
        Mock -ModuleName $ModuleName Set-RegistryValue { }

        (Set-WindowsBaseline -Id 'LLMNR-Disabled' -Confirm:$false).Reason | Should -Be 'value not set'
    }
}

Describe 'New-BaselineReport' {
    It 'summarizes a mixed result' {
        Mock -ModuleName $ModuleName Get-RegistryValue {
            param($Path, $Name)
            if ($Name -eq 'SMB1') { 1 } else { $null }
        }

        $report = Test-WindowsBaseline | New-BaselineReport

        $report.Total        | Should -Be (Get-BaselineControl).Count
        $report.NonCompliant | Should -Be $report.Total
        $report.Compliant    | Should -Be 0
        $report.HighSeverity | Should -BeGreaterThan 0
        $report.Failing.Count | Should -Be $report.Total
    }

    It 'reports a fully compliant machine as 100 percent' {
        Mock -ModuleName $ModuleName Get-RegistryValue {
            param($Path, $Name)
            switch ($Name) {
                'UserAuthentication'       { 1 }
                'EnableScriptBlockLogging' { 1 }
                'LmCompatibilityLevel'     { 5 }
                default                    { 0 }
            }
        }

        $report = Test-WindowsBaseline | New-BaselineReport

        $report.NonCompliant  | Should -Be 0
        $report.CompliantRate | Should -Be 100
        $report.Failing.Count | Should -Be 0
    }

    It 'survives a round trip through JSON, which is how the pipeline reads it' {
        Mock -ModuleName $ModuleName Get-RegistryValue { 1 }

        $json = Test-WindowsBaseline | New-BaselineReport | ConvertTo-Json -Depth 6
        $parsed = $json | ConvertFrom-Json

        $parsed.Total | Should -Be (Get-BaselineControl).Count
        $parsed.GeneratedAt | Should -Not -BeNullOrEmpty
    }
}
