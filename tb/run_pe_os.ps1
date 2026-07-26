[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Icarus', 'Verilator')]
    [string] $Simulator = 'Auto',
    [string] $Rtl = (Join-Path $PSScriptRoot '..\rtl\pe_os.sv')
)

$ErrorActionPreference = 'Stop'

$testbench = Join-Path $PSScriptRoot 'tb_pe_os.sv'
$buildDir = Join-Path $PSScriptRoot 'sim_build'

if (-not (Test-Path -LiteralPath $Rtl -PathType Leaf)) {
    throw "PE RTL was not found: $Rtl"
}

$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
$vvp = Get-Command vvp -ErrorAction SilentlyContinue
$verilator = Get-Command verilator -ErrorAction SilentlyContinue

if ($Simulator -eq 'Auto') {
    if ($iverilog -and $vvp) {
        $Simulator = 'Icarus'
    } elseif ($verilator) {
        $Simulator = 'Verilator'
    } else {
        throw 'No supported simulator was found. Install Icarus Verilog (iverilog + vvp) or Verilator, then rerun this script.'
    }
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

if ($Simulator -eq 'Icarus') {
    if (-not ($iverilog -and $vvp)) {
        throw 'Icarus Verilog was selected, but iverilog and/or vvp is not available on PATH.'
    }

    $output = Join-Path $buildDir 'tb_pe_os.vvp'
    & $iverilog.Source '-g2012' '-Wall' '-s' 'tb_pe_os' '-o' $output $Rtl $testbench
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $vvp.Source $output
    exit $LASTEXITCODE
}

if (-not $verilator) {
    throw 'Verilator was selected, but verilator is not available on PATH.'
}

& $verilator.Source '--binary' '--timing' '-Wall' '--top-module' 'tb_pe_os' '--Mdir' $buildDir $Rtl $testbench
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$binary = Join-Path $buildDir 'Vtb_pe_os.exe'
if (-not (Test-Path -LiteralPath $binary)) {
    $binary = Join-Path $buildDir 'Vtb_pe_os'
}
& $binary
exit $LASTEXITCODE
