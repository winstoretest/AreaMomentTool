<#
.SYNOPSIS
    Tests Alibre Design Add-On registry key install/uninstall logic.

.DESCRIPTION
    Validates the registry operations for Alibre Design Add-Ons:
    - Creates string value at HKLM\SOFTWARE\Alibre, Inc.\Alibre Design Add-Ons
    - Value name = AddonName, Value data = Path to addon folder
    - Reads back and verifies
    - Removes the value (uninstall)
    - Verifies removal

    Correct registry format:
    HKLM\SOFTWARE\Alibre, Inc.\Alibre Design Add-Ons
        AddonName = "C:\Program Files\Alibre Design Add-Ons\AddonName"  (REG_SZ)

.PARAMETER AddonName
    Name of the addon to test. Default is "TestAddon".

.PARAMETER AddonPath
    Path value to set. Default is "C:\Program Files\Alibre Design Add-Ons\TestAddon".

.PARAMETER SkipCleanup
    Don't remove the test registry value after testing.

.EXAMPLE
    .\Test-AddonRegistry.ps1

    Tests with default values.

.EXAMPLE
    .\Test-AddonRegistry.ps1 -AddonName "MyAddon" -AddonPath "D:\Addons\MyAddon"

    Tests with custom addon name and path.

.NOTES
    Requires Administrator privileges to write to HKLM.
#>

[CmdletBinding()]
param(
    [string]$AddonName = "TestAddon",
    [string]$AddonPath = "C:\Program Files\Alibre Design Add-Ons\TestAddon",
    [switch]$SkipCleanup
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# The addon is registered as a STRING VALUE on this key (not a subkey)
$script:AlibreRegistryKey = "HKLM:\SOFTWARE\Alibre, Inc.\Alibre Design Add-Ons"
$script:TestResults = @()
$script:PassCount = 0
$script:FailCount = 0

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Banner {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  ALIBRE DESIGN ADD-ON REGISTRY TESTER" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  Addon Name:  $AddonName" -ForegroundColor Gray
    Write-Host "  Addon Path:  $AddonPath" -ForegroundColor Gray
    Write-Host "  Registry:    $script:AlibreRegistryKey" -ForegroundColor Gray
    Write-Host "  Value:       $AddonName = `"$AddonPath`"" -ForegroundColor Gray
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$Description
    )

    Write-Host "  [$($script:TestResults.Count + 1)] $Name" -ForegroundColor White -NoNewline

    try {
        $result = & $Test
        if ($result) {
            Write-Host " PASS" -ForegroundColor Green
            $script:PassCount++
            $script:TestResults += @{
                Name = $Name
                Description = $Description
                Status = "PASS"
                Error = $null
            }
            return $true
        } else {
            Write-Host " FAIL" -ForegroundColor Red
            $script:FailCount++
            $script:TestResults += @{
                Name = $Name
                Description = $Description
                Status = "FAIL"
                Error = "Test returned false"
            }
            return $false
        }
    }
    catch {
        Write-Host " FAIL" -ForegroundColor Red
        Write-Host "      Error: $_" -ForegroundColor DarkRed
        $script:FailCount++
        $script:TestResults += @{
            Name = $Name
            Description = $Description
            Status = "FAIL"
            Error = $_.Exception.Message
        }
        return $false
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor DarkCyan
    Write-Host ""
}

# ==============================================================================
# REGISTRY OPERATIONS (Same logic as installer)
# ==============================================================================

function Install-AddonRegistryValue {
    <#
    .SYNOPSIS
        Creates the registry value for an Alibre Design Add-On.
        This mirrors what the Inno Setup installer does.

        Format: HKLM\SOFTWARE\Alibre, Inc.\Alibre Design Add-Ons
                    AddonName = "C:\Path\To\Addon"  (REG_SZ)
    #>
    param(
        [string]$Name,
        [string]$Path
    )

    # Ensure the Add-Ons key exists
    if (-not (Test-Path $script:AlibreRegistryKey)) {
        New-Item -Path $script:AlibreRegistryKey -Force | Out-Null
    }

    # Set the addon as a string value (ValueName = AddonName, ValueData = Path)
    Set-ItemProperty -Path $script:AlibreRegistryKey -Name $Name -Value $Path -Type String
}

function Uninstall-AddonRegistryValue {
    <#
    .SYNOPSIS
        Removes the registry value for an Alibre Design Add-On.
        This mirrors what the Inno Setup uninstaller does.
    #>
    param(
        [string]$Name
    )

    if (Test-Path $script:AlibreRegistryKey) {
        $existing = Get-ItemProperty -Path $script:AlibreRegistryKey -Name $Name -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-ItemProperty -Path $script:AlibreRegistryKey -Name $Name -ErrorAction SilentlyContinue
        }
    }
}

function Get-AddonRegistryValue {
    <#
    .SYNOPSIS
        Reads the registry value for an Alibre Design Add-On.
    #>
    param(
        [string]$Name
    )

    if (Test-Path $script:AlibreRegistryKey) {
        $props = Get-ItemProperty -Path $script:AlibreRegistryKey -ErrorAction SilentlyContinue
        if ($props.PSObject.Properties.Name -contains $Name) {
            return @{
                Exists = $true
                Path = $props.$Name
            }
        }
    }

    return @{
        Exists = $false
        Path = $null
    }
}

function Get-AllAddonRegistryValues {
    <#
    .SYNOPSIS
        Lists all registered Alibre Design Add-Ons.
    #>

    $addons = @()

    if (Test-Path $script:AlibreRegistryKey) {
        $props = Get-ItemProperty -Path $script:AlibreRegistryKey -ErrorAction SilentlyContinue
        foreach ($prop in $props.PSObject.Properties) {
            # Skip PowerShell metadata properties
            if ($prop.Name -notmatch '^PS') {
                $addons += @{
                    Name = $prop.Name
                    Path = $prop.Value
                }
            }
        }
    }

    return $addons
}

# ==============================================================================
# TEST EXECUTION
# ==============================================================================

function Invoke-Tests {
    Write-Banner

    # Check admin privileges
    Write-Section "PREREQUISITES"

    $isAdmin = Test-Step -Name "Administrator privileges" -Description "Check if running as admin" -Test {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "  ERROR: This script requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Please run PowerShell as Administrator and try again." -ForegroundColor Red
        Write-Host ""
        return
    }

    # Check if Alibre base key exists
    Test-Step -Name "Alibre Design registry exists" -Description "Check if Alibre Design is installed" -Test {
        Test-Path "HKLM:\SOFTWARE\Alibre, Inc.\Alibre Design"
    }

    Test-Step -Name "Alibre Add-Ons key exists" -Description "Check if Add-Ons key exists" -Test {
        Test-Path $script:AlibreRegistryKey
    }

    # List existing addons
    Write-Section "EXISTING ADD-ONS"
    $existingAddons = Get-AllAddonRegistryValues
    if ($existingAddons.Count -gt 0) {
        foreach ($addon in $existingAddons) {
            Write-Host "      $($addon.Name) = $($addon.Path)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "      (none)" -ForegroundColor DarkGray
    }

    # Clean any existing test value
    Write-Section "CLEANUP (Pre-test)"

    Test-Step -Name "Remove existing test value (if any)" -Description "Clean slate for testing" -Test {
        $existing = Get-AddonRegistryValue -Name $AddonName
        if ($existing.Exists) {
            Uninstall-AddonRegistryValue -Name $AddonName
            Write-Host " (removed existing)" -ForegroundColor DarkGray -NoNewline
        }
        return $true
    }

    # INSTALL TESTS
    Write-Section "INSTALL TESTS"

    Test-Step -Name "Create addon registry value" -Description "Install-AddonRegistryValue creates the value" -Test {
        Install-AddonRegistryValue -Name $AddonName -Path $AddonPath
        return $true
    }

    Test-Step -Name "Verify value exists" -Description "Value should exist after install" -Test {
        $info = Get-AddonRegistryValue -Name $AddonName
        return $info.Exists
    }

    Test-Step -Name "Verify Path data" -Description "Path data should match" -Test {
        $info = Get-AddonRegistryValue -Name $AddonName
        return ($info.Path -eq $AddonPath)
    }

    Test-Step -Name "Read value directly" -Description "Direct registry read" -Test {
        $value = (Get-ItemProperty -Path $script:AlibreRegistryKey -Name $AddonName).$AddonName
        return ($value -eq $AddonPath)
    }

    Test-Step -Name "Value appears in addon list" -Description "Should be in Get-AllAddonRegistryValues" -Test {
        $addons = Get-AllAddonRegistryValues
        $found = $addons | Where-Object { $_.Name -eq $AddonName }
        return ($null -ne $found)
    }

    # UPDATE TESTS
    Write-Section "UPDATE TESTS"

    $newPath = "$AddonPath-Updated"
    Test-Step -Name "Update Path value" -Description "Modify existing value" -Test {
        Install-AddonRegistryValue -Name $AddonName -Path $newPath
        $info = Get-AddonRegistryValue -Name $AddonName
        return ($info.Path -eq $newPath)
    }

    Test-Step -Name "Restore original Path" -Description "Reset to original value" -Test {
        Install-AddonRegistryValue -Name $AddonName -Path $AddonPath
        $info = Get-AddonRegistryValue -Name $AddonName
        return ($info.Path -eq $AddonPath)
    }

    # UNINSTALL TESTS
    Write-Section "UNINSTALL TESTS"

    Test-Step -Name "Remove addon registry value" -Description "Uninstall-AddonRegistryValue removes the value" -Test {
        Uninstall-AddonRegistryValue -Name $AddonName
        return $true
    }

    Test-Step -Name "Verify value removed" -Description "Value should not exist after uninstall" -Test {
        $info = Get-AddonRegistryValue -Name $AddonName
        return (-not $info.Exists)
    }

    Test-Step -Name "Verify Path data gone" -Description "Path data should be null" -Test {
        $info = Get-AddonRegistryValue -Name $AddonName
        return ($null -eq $info.Path)
    }

    Test-Step -Name "Value not in addon list" -Description "Should not be in Get-AllAddonRegistryValues" -Test {
        $addons = Get-AllAddonRegistryValues
        $found = $addons | Where-Object { $_.Name -eq $AddonName }
        return ($null -eq $found)
    }

    # IDEMPOTENCY TESTS
    Write-Section "IDEMPOTENCY TESTS"

    Test-Step -Name "Uninstall non-existent value (no error)" -Description "Should not throw" -Test {
        Uninstall-AddonRegistryValue -Name $AddonName
        Uninstall-AddonRegistryValue -Name $AddonName  # Second call
        return $true
    }

    Test-Step -Name "Install twice (idempotent)" -Description "Should succeed on repeated calls" -Test {
        Install-AddonRegistryValue -Name $AddonName -Path $AddonPath
        Install-AddonRegistryValue -Name $AddonName -Path $AddonPath
        $info = Get-AddonRegistryValue -Name $AddonName
        return ($info.Exists -and $info.Path -eq $AddonPath)
    }

    # CLEANUP
    if (-not $SkipCleanup) {
        Write-Section "CLEANUP (Post-test)"

        Test-Step -Name "Final cleanup" -Description "Remove test registry value" -Test {
            Uninstall-AddonRegistryValue -Name $AddonName
            $info = Get-AddonRegistryValue -Name $AddonName
            return (-not $info.Exists)
        }
    } else {
        Write-Host ""
        Write-Host "  [!] Skipping cleanup (-SkipCleanup specified)" -ForegroundColor Yellow
        Write-Host "      Value remains: $script:AlibreRegistryKey\$AddonName" -ForegroundColor DarkGray
    }

    # SUMMARY
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Total:  $($script:TestResults.Count)" -ForegroundColor White
    Write-Host "  Passed: $script:PassCount" -ForegroundColor Green
    Write-Host "  Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""

    if ($script:FailCount -gt 0) {
        Write-Host "  Failed Tests:" -ForegroundColor Red
        foreach ($test in ($script:TestResults | Where-Object { $_.Status -eq "FAIL" })) {
            Write-Host "    - $($test.Name): $($test.Error)" -ForegroundColor DarkRed
        }
        Write-Host ""
    }

    $status = if ($script:FailCount -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($script:FailCount -eq 0) { "Green" } else { "Red" }
    Write-Host "  Result: $status" -ForegroundColor $color
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($script:FailCount -gt 0) {
        exit 1
    }
}

# ==============================================================================
# MAIN
# ==============================================================================

Invoke-Tests
