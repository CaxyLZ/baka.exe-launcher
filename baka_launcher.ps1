Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    public static IntPtr FindWindowByPID(int pid) {
        IntPtr result = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            uint wpid = 0;
            GetWindowThreadProcessId(hWnd, out wpid);
            if (wpid == (uint)pid) {
                result = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}

public class MCI {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string lpstrCommand, StringBuilder lpstrReturnString, int uReturnLength, IntPtr hwndCallback);
}
"@

[Win32]::SetProcessDPIAware() | Out-Null

$scriptDir   = $PSScriptRoot
$exePath     = Join-Path $scriptDir "baka.exe"
$musicFolder = Join-Path $scriptDir "music"

if (-not (Test-Path -LiteralPath $exePath)) {
    [System.Windows.Forms.MessageBox]::Show("找不到: $exePath", "错误")
    exit 1
}

if (-not (Test-Path -LiteralPath $musicFolder)) {
    New-Item -ItemType Directory -Path $musicFolder -Force | Out-Null
}

$global:BakaList    = New-Object System.Collections.ArrayList
$global:Dancing     = $false
$global:DanceStart  = $null
$global:MusicAlias  = $null
$global:MusicOpened = $false

function Test-BakaCount($raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [PSCustomObject]@{ OK=$false; Msg="你在干嘛。。。"; Zero=$false }
    }
    $num = 0.0
    if (-not [double]::TryParse($raw.Trim(), [ref]$num)) {
        return [PSCustomObject]@{ OK=$false; Msg="你在干嘛。。。"; Zero=$false }
    }
    if ($num -ne [Math]::Floor($num)) {
        return [PSCustomObject]@{ OK=$false; Msg="不存在半只baka这种情况！"; Zero=$false }
    }
    if ($num -eq 0) {
        return [PSCustomObject]@{ OK=$false; Msg="滚木baka已经在你的电脑上了。"; Zero=$true }
    }
    if ($num -lt 0) {
        $abs = [Math]::Abs($num)
        return [PSCustomObject]@{ OK=$false; Msg="好了，你现在欠我$abs只baka了"; Zero=$false }
    }
    if ($num -gt 100) {
        return [PSCustomObject]@{ OK=$false; Msg="最多只有100只baka哦~"; Zero=$false }
    }
    return [PSCustomObject]@{ OK=$true; Count=[int]$num; Msg=""; Zero=$false }
}

function Show-Ghost {
    $tempExe = Join-Path $env:TEMP "滚木baka.exe"
    try {
        Copy-Item -LiteralPath "$env:SystemRoot\System32\PING.EXE" -Destination $tempExe -Force -ErrorAction Stop
    } catch {
        $tempExe = Join-Path $env:TEMP "滚木baka_$(Get-Random -Maximum 9999).exe"
        Copy-Item -LiteralPath "$env:SystemRoot\System32\PING.EXE" -Destination $tempExe -Force
    }
    Start-Process -FilePath $tempExe -ArgumentList "-n 1 127.0.0.1" -WindowStyle Hidden
    $cleanup = "Start-Sleep -Seconds 2; Remove-Item -LiteralPath '$tempExe' -Force -ErrorAction SilentlyContinue"
    Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", $cleanup
}

function Start-Bakas($count) {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    for ($i = 1; $i -le $count; $i++) {
        $proc = Start-Process -FilePath $exePath -PassThru
        $hWnd = [IntPtr]::Zero
        for ($t = 0; $t -lt 60; $t++) {
            Start-Sleep -Milliseconds 50
            $proc.Refresh()
            if ($proc.HasExited) { break }
            $hWnd = [Win32]::FindWindowByPID($proc.Id)
            if ($hWnd -ne [IntPtr]::Zero) { break }
        }
        if ($hWnd -ne [IntPtr]::Zero) {
            [Win32]::ShowWindow($hWnd, 0) | Out-Null
            $rect = New-Object Win32+RECT
            [Win32]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            $w = $rect.Right - $rect.Left
            $h = $rect.Bottom - $rect.Top
            if ($w -le 0) { $w = 200 }
            if ($h -le 0) { $h = 200 }
            $maxX = [Math]::Max(0, $screen.Width - $w)
            $maxY = [Math]::Max(0, $screen.Height - $h)
            $x = Get-Random -Minimum 0 -Maximum ($maxX + 1)
            $y = Get-Random -Minimum 0 -Maximum ($maxY + 1)
            [Win32]::MoveWindow($hWnd, $x, $y, $w, $h, $false) | Out-Null
            [Win32]::ShowWindow($hWnd, 8) | Out-Null
            $global:BakaList.Add([PSCustomObject]@{
                Handle    = $hWnd
                BaseX     = $x
                BaseY     = $y
                BaseW     = $w
                BaseH     = $h
                Amplitude = [int]($h * 0.5)
                Period    = 1.0
                Delay     = 0.0
            }) | Out-Null
        }
        Start-Sleep -Milliseconds 30
    }
}

function Start-Music {
    $files = @()
    if (Test-Path -LiteralPath $musicFolder) {
        $files = Get-ChildItem -Path $musicFolder -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -match '^\.(mp3|wav|wma|m4a|aac)$' }
    }
    if ($files.Count -eq 0) { return }

    $pick = $files | Get-Random
    $alias = "bakamusic_$(Get-Random -Maximum 99999)"

    $openCmd = "open `"$($pick.FullName)`" alias $alias"
    $r1 = [MCI]::mciSendString($openCmd, $null, 0, [IntPtr]::Zero)
    if ($r1 -ne 0) {
        Write-Host "MCI open failed: $r1  file=$($pick.FullName)"
        return
    }

    $playCmd = "play $alias"
    $r2 = [MCI]::mciSendString($playCmd, $null, 0, [IntPtr]::Zero)
    if ($r2 -ne 0) {
        Write-Host "MCI play failed: $r2"
        [MCI]::mciSendString("close $alias", $null, 0, [IntPtr]::Zero) | Out-Null
        return
    }

    $global:MusicAlias  = $alias
    $global:MusicOpened = $true
}

function Stop-Music {
    if ($global:MusicAlias) {
        try {
            [MCI]::mciSendString("stop $($global:MusicAlias)", $null, 0, [IntPtr]::Zero) | Out-Null
            [MCI]::mciSendString("close $($global:MusicAlias)", $null, 0, [IntPtr]::Zero) | Out-Null
        } catch {}
        $global:MusicAlias  = $null
        $global:MusicOpened = $false
    }
}

function Test-MusicEnded {
    if (-not $global:MusicAlias) { return $false }
    $buf = New-Object System.Text.StringBuilder 64
    $r = [MCI]::mciSendString("status $($global:MusicAlias) mode", $buf, 64, [IntPtr]::Zero)
    if ($r -ne 0) { return $true }
    $mode = $buf.ToString().Trim()
    if ($mode -eq "stopped") { return $true }
    return $false
}

function Start-Dance {
    if ($global:BakaList.Count -eq 0) { return }
    foreach ($b in $global:BakaList) {
        if (-not [Win32]::IsWindow($b.Handle)) { continue }
        $rect = New-Object Win32+RECT
        [Win32]::GetWindowRect($b.Handle, [ref]$rect) | Out-Null
        $b.BaseX = $rect.Left
        $b.BaseY = $rect.Top
        $b.BaseW = $rect.Right - $rect.Left
        $b.BaseH = $rect.Bottom - $rect.Top
        if ($b.BaseW -le 0) { $b.BaseW = 200 }
        if ($b.BaseH -le 0) { $b.BaseH = 200 }
        $b.Amplitude = [int]($b.BaseH * 0.5)
        $b.Period = Get-Random -Minimum 0.8 -Maximum 1.1
        $b.Delay  = Get-Random -Minimum 0.0 -Maximum 0.1
    }
    $global:DanceStart = [System.Diagnostics.Stopwatch]::StartNew()
    $global:Dancing = $true
    Start-Music
}

function Stop-Dance {
    $global:Dancing = $false
    Stop-Music
    foreach ($b in $global:BakaList) {
        if ([Win32]::IsWindow($b.Handle)) {
            [Win32]::MoveWindow($b.Handle, $b.BaseX, $b.BaseY, $b.BaseW, $b.BaseH, $true) | Out-Null
        }
    }
    if ($global:DanceStart) { $global:DanceStart.Stop() }
    $global:DanceStart = $null
}

function Kill-AllBakas {
    Stop-Dance
    # 强制结束所有 baka.exe 和 滚木baka.exe
    & taskkill /F /IM baka.exe /T *> $null
    & taskkill /F /IM 滚木baka.exe /T *> $null
    $global:BakaList.Clear()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "baka launcher"
$form.Size = New-Object System.Drawing.Size(320, 280)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $false

$label = New-Object System.Windows.Forms.Label
$label.Text = "需要多少只baka？"
$label.Location = New-Object System.Drawing.Point(20, 15)
$label.Size = New-Object System.Drawing.Size(260, 20)
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Text = "5"
$textBox.Location = New-Object System.Drawing.Point(20, 40)
$textBox.Size = New-Object System.Drawing.Size(260, 25)
$form.Controls.Add($textBox)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "启动"
$btnStart.Location = New-Object System.Drawing.Point(20, 80)
$btnStart.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnStart)

$btnDance = New-Object System.Windows.Forms.Button
$btnDance.Text = "???"
$btnDance.Location = New-Object System.Drawing.Point(160, 80)
$btnDance.Size = New-Object System.Drawing.Size(120, 40)
$form.Controls.Add($btnDance)

# 新增：一键关闭按钮 (红色)
$btnKill = New-Object System.Windows.Forms.Button
$btnKill.Text = "物理超度 (关闭全部)"
$btnKill.Location = New-Object System.Drawing.Point(20, 130)
$btnKill.Size = New-Object System.Drawing.Size(260, 35)
$btnKill.BackColor = [System.Drawing.Color]::FromArgb(220, 80, 80)
$btnKill.ForeColor = [System.Drawing.Color]::White
$btnKill.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnKill.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnKill)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(20, 180)
$statusLabel.Size = New-Object System.Drawing.Size(260, 40)
$form.Controls.Add($statusLabel)

$btnStart.Add_Click({
    $result = Test-BakaCount $textBox.Text
    if (-not $result.OK) {
        if ($result.Zero) { Show-Ghost }
        [System.Windows.Forms.MessageBox]::Show($result.Msg, "错误") | Out-Null
        return
    }
    Start-Bakas $result.Count
    $statusLabel.Text = "已启动 $($global:BakaList.Count) 只baka"
})

$btnDance.Add_Click({
    if ($global:Dancing) {
        Stop-Dance
        $statusLabel.Text = "停止跳舞"
    } else {
        if ($global:BakaList.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("还没有启动baka哦", "提示") | Out-Null
            return
        }
        Start-Dance
        $statusLabel.Text = "跳舞中..."
    }
})

$btnKill.Add_Click({
    Kill-AllBakas
    $statusLabel.Text = "所有 baka 已被物理超度！"
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 16
$timer.Add_Tick({
    if (-not $global:Dancing) { return }
    $elapsed = $global:DanceStart.Elapsed.TotalSeconds
    foreach ($b in $global:BakaList) {
        if (-not [Win32]::IsWindow($b.Handle)) { continue }
        $t = $elapsed - $b.Delay
        if ($t -lt 0) { continue }
        $phase = ($t / $b.Period) % 1.0
        $scale = [Math]::Abs([Math]::Sin($phase * [Math]::PI))
        $offset = [int]($b.Amplitude * $scale)
        $newY = $b.BaseY - $offset
        [Win32]::MoveWindow($b.Handle, $b.BaseX, $newY, $b.BaseW, $b.BaseH, $false) | Out-Null
    }
    if ($global:MusicOpened -and (Test-MusicEnded)) {
        Stop-Dance
        $statusLabel.Text = "音乐结束，停止跳舞"
    }
})
$timer.Start()

$form.Add_FormClosing({
    Stop-Dance
    $timer.Stop()
})

[void]$form.ShowDialog()
