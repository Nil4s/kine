param([string]$HwndFile, [int]$Owner = 0, [int]$W = 1600, [int]$H = 900)
# THE OFF-SCREEN HOST for tools/run_all.sh's window suites. Godot clamps a --position that is off every screen back onto
# the screen (its window lands at 0,0, measured 10-23), so the window suites are instead started with --wid <this
# window>: Godot's window becomes a CHILD of this one, which sits at -30000,-30000, is never activated (no focus
# stealing) and has no taskbar button. Child windows render exactly as top-level ones do (viewport screenshots incl.).
# Its HWND goes to $HwndFile. It closes when that file is deleted or when the runner ($Owner, a Windows PID) is gone.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System; using System.Windows.Forms;
public class KineTestHost : Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { var p = base.CreateParams; p.ExStyle |= 0x08000000 | 0x00000080; return p; } }  // NOACTIVATE | TOOLWINDOW
}
"@
$f = New-Object KineTestHost
$f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(-30000, -30000)
$f.FormBorderStyle = 'None'; $f.ClientSize = New-Object System.Drawing.Size($W, $H); $f.ShowInTaskbar = $false
$f.Text = 'kine-test-host'
$t = New-Object System.Windows.Forms.Timer; $t.Interval = 1000
$t.Add_Tick({
  if (-not (Test-Path $HwndFile)) { $f.Close() }
  elseif ($Owner -gt 0 -and -not (Get-Process -Id $Owner -ErrorAction SilentlyContinue)) { Remove-Item $HwndFile -ErrorAction SilentlyContinue; $f.Close() }
})
$f.Add_Shown({ Set-Content -Path "$HwndFile.tmp" -Value ([int64]$f.Handle) -Encoding ascii; Move-Item -Force "$HwndFile.tmp" $HwndFile; $t.Start() })
[System.Windows.Forms.Application]::Run($f)
