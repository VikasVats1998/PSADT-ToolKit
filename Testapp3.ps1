#requires -Version 5.1
<#  HelpDesk-Maintenance.UITest.ps1  (app2.ps1)
    UI-only walkthrough. NO real actions. ASCII-only (no em-dashes) to avoid encoding breakage.
#>
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$Clr = @{ Action='#C00000'; Cancel='#2E7D32'; Accent='#1F4E79'; Ink='#111111' }
$script:Flow = [ordered]@{ Domain=$null; User=$null; PC=$null; Selection=$null }

function C  { param([string]$hex) [System.Windows.Media.BrushConverter]::new().ConvertFromString($hex) }
function T  { param([double]$l,[double]$t=[double]::NaN,[double]$r=0,[double]$b=0)
             if([double]::IsNaN($t)){ [System.Windows.Thickness]::new($l) } else { [System.Windows.Thickness]::new($l,$t,$r,$b) } }
function Get-Sim { if($script:SimCombo.SelectedItem -eq 'Failure'){'Failure'}else{'Success'} }
function Get-Val { param($tb) if($tb.Text -eq $tb.Tag){''}else{$tb.Text} }

function New-Btn {
    param([string]$Text,[string]$Fg,[scriptblock]$OnClick)
    $b = New-Object System.Windows.Controls.Button
    $b.Content=$Text; $b.MinWidth=110; $b.Margin=(T 0,0,12,0); $b.Padding=(T 16,8,16,8)
    $b.Foreground=(C $Fg); $b.BorderBrush=(C $Clr.Accent); $b.BorderThickness=(T 2)
    $b.Background=[System.Windows.Media.Brushes]::White; $b.FontWeight='SemiBold'; $b.Cursor='Hand'
    if($OnClick){ $b.Add_Click($OnClick) }
    $b
}
function New-Input {
    param([string]$Placeholder)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Tag=$Placeholder; $tb.Text=$Placeholder; $tb.Foreground=(C '#8a8a8a')
    $tb.Width=260; $tb.HorizontalAlignment='Left'; $tb.Padding=(T 6,4,6,4)
    $tb.BorderBrush=(C $Clr.Accent); $tb.BorderThickness=(T 2)
    $tb.Add_GotFocus({  if($this.Text -eq $this.Tag){ $this.Text=''; $this.Foreground=(C '#111111') } })
    $tb.Add_LostFocus({ if([string]::IsNullOrEmpty($this.Text)){ $this.Text=$this.Tag; $this.Foreground=(C '#8a8a8a') } })
    $tb
}
function Row { param([System.Windows.UIElement[]]$Items)
    $sp=New-Object System.Windows.Controls.StackPanel; $sp.Orientation='Horizontal'; $sp.Margin=(T 0,20,0,0)
    foreach($i in $Items){ $sp.Children.Add($i)|Out-Null }; $sp
}
function New-Screen {
    param([string]$Heading)
    $root=New-Object System.Windows.Controls.StackPanel; $root.Margin=(T 26)
    $brand=New-Object System.Windows.Controls.StackPanel; $brand.Orientation='Horizontal'
    $el=New-Object System.Windows.Shapes.Ellipse; $el.Width=26; $el.Height=26; $el.Stroke=(C $Clr.Ink); $el.StrokeThickness=2; $el.Margin=(T 0,0,10,0); $el.VerticalAlignment='Center'
    $tt=New-Object System.Windows.Controls.StackPanel
    $t1=New-Object System.Windows.Controls.TextBlock; $t1.Text='IT Help Desk'; $t1.FontSize=20; $t1.FontWeight='Bold'; $t1.FontStyle='Italic'
    $t2=New-Object System.Windows.Controls.TextBlock; $t2.Text='LZFD Karlsruhe Maintenance'; $t2.FontSize=11; $t2.Foreground=(C '#555')
    $tt.Children.Add($t1)|Out-Null; $tt.Children.Add($t2)|Out-Null
    $brand.Children.Add($el)|Out-Null; $brand.Children.Add($tt)|Out-Null; $root.Children.Add($brand)|Out-Null
    if($Heading){ $h=New-Object System.Windows.Controls.TextBlock; $h.Text=$Heading; $h.FontSize=15; $h.Margin=(T 0,22,0,10); $h.TextWrapping='Wrap'; $root.Children.Add($h)|Out-Null }
    $root
}
function Set-Screen { param($el) $script:ContentHost.Content=$el }

function Show-Login {
    $s=New-Screen
    $s.Children.Add((Row @((New-Btn 'Login' $Clr.Action { Show-Domain }),(New-Btn 'Cancel' $Clr.Cancel { $script:Win.Close() }))))|Out-Null
    Set-Screen $s
}
function Show-Domain {
    $s=New-Screen
    1..4 | ForEach-Object { $tb=New-Object System.Windows.Controls.TextBlock; $tb.Text="$_.  -  Domain $_"; $tb.FontSize=14; $tb.Margin=(T 0,2,0,2); $s.Children.Add($tb)|Out-Null }
    $combo=New-Object System.Windows.Controls.ComboBox; $combo.Width=220; $combo.HorizontalAlignment='Left'; $combo.Margin=(T 0,10,0,0)
    1..4 | ForEach-Object { $combo.Items.Add("Domain $_")|Out-Null }; $combo.SelectedIndex=0
    $s.Children.Add($combo)|Out-Null
    $s.Children.Add((Row @((New-Btn 'Next' $Clr.Action { $script:Flow.Domain=$combo.SelectedItem; Show-User }))))|Out-Null
    Set-Screen $s
}
function Show-User {
    $s=New-Screen 'Domain Name'
    $dom=New-Object System.Windows.Controls.TextBlock; $dom.Text=[string]$script:Flow.Domain; $dom.FontWeight='SemiBold'; $dom.Margin=(T 0,0,0,10); $s.Children.Add($dom)|Out-Null
    $u=New-Input 'User'; $s.Children.Add($u)|Out-Null
    $s.Children.Add((Row @((New-Btn 'Next' $Clr.Action { $script:Flow.User=(Get-Val $u); Show-Password }))))|Out-Null
    Set-Screen $s
}
function Show-Password {
    $s=New-Screen 'Password'
    $pb=New-Object System.Windows.Controls.PasswordBox; $pb.Width=260; $pb.HorizontalAlignment='Left'; $pb.Padding=(T 6,4,6,4); $pb.BorderBrush=(C $Clr.Accent); $pb.BorderThickness=(T 2)
    $s.Children.Add($pb)|Out-Null
    $s.Children.Add((Row @((New-Btn 'Login' $Clr.Action { Show-Analyzing }))))|Out-Null
    Set-Screen $s
}
function Show-Analyzing {
    $s=New-Screen
    $t=New-Object System.Windows.Controls.TextBlock; $t.Text='Analyzing ....'; $t.Margin=(T 0,24,0,10)
    $pb=New-Object System.Windows.Controls.ProgressBar; $pb.IsIndeterminate=$true; $pb.Height=16
    $s.Children.Add($t)|Out-Null; $s.Children.Add($pb)|Out-Null; Set-Screen $s
    $timer=New-Object System.Windows.Threading.DispatcherTimer; $timer.Interval=[TimeSpan]::FromSeconds(1.5)
    $timer.Add_Tick({ $this.Stop(); if((Get-Sim) -eq 'Success'){ Show-EnterPC } else { Show-Failed { Show-Analyzing } } })
    $timer.Start()
}
function Show-EnterPC {
    $s=New-Screen 'Successful - Enter PC Name'
    $pc=New-Input 'Computer Name'; $s.Children.Add($pc)|Out-Null
    $connect=New-Btn 'Connect' $Clr.Action { $script:Flow.PC=(Get-Val $pc); if((Get-Sim) -eq 'Success'){ Show-Read } else { Show-Failed { Show-EnterPC } } }
    $s.Children.Add((Row @($connect,(New-Btn 'Cancel' $Clr.Cancel { Show-Login }))))|Out-Null
    Set-Screen $s
}
function Show-Read {
    $s=New-Screen 'Successful - Read the Reg Keys'
    $read=New-Btn 'Read' $Clr.Action { if((Get-Sim) -eq 'Success'){ Show-RegList } else { Show-Failed { Show-Read } } }
    $s.Children.Add((Row @($read,(New-Btn 'Cancel' $Clr.Cancel { Show-Login }))))|Out-Null
    Set-Screen $s
}
function Show-RegList {
    $s=New-Screen
    1..5 | ForEach-Object { $tb=New-Object System.Windows.Controls.TextBlock; $tb.Text=("{0}.   {{ - - - - - - - }}" -f $_); $tb.FontFamily='Consolas'; $tb.Margin=(T 0,2,0,2); $s.Children.Add($tb)|Out-Null }
    $lbl=New-Object System.Windows.Controls.TextBlock; $lbl.Text='Select the Numbers (e.g. 2,4,5):'; $lbl.Margin=(T 0,12,0,4); $s.Children.Add($lbl)|Out-Null
    $sel=New-Input '2,4,5'; $s.Children.Add($sel)|Out-Null
    $del=New-Btn 'Delete' $Clr.Action { $script:Flow.Selection=(Get-Val $sel); if((Get-Sim) -eq 'Success'){ Show-Reboot } else { Show-Failed { Show-RegList } } }
    $s.Children.Add((Row @($del,(New-Btn 'Cancel' $Clr.Cancel { Show-Login }))))|Out-Null
    Set-Screen $s
}
function Show-Reboot {
    $s=New-Screen 'Successful - Trigger Reboot'
    $s.Children.Add((Row @((New-Btn 'Reboot' $Clr.Action { Show-Done }),(New-Btn 'Close' $Clr.Cancel { $script:Win.Close() }))))|Out-Null
    Set-Screen $s
}
function Show-Done {
    $s=New-Screen ("Maintenance Successful for PC {{{0}}}" -f $script:Flow.PC)
    $s.Children.Add((Row @((New-Btn 'Start New' $Clr.Action { Show-EnterPC }),(New-Btn 'Close' $Clr.Cancel { $script:Win.Close() }))))|Out-Null
    Set-Screen $s
}
function Show-Failed {
    param([scriptblock]$Retry)
    $script:RetryAction=$Retry
    $s=New-Screen 'Failed'
    $s.Children.Add((Row @((New-Btn 'Try Again' $Clr.Action { & $script:RetryAction }),(New-Btn 'Cancel' $Clr.Cancel { Show-Login }))))|Out-Null
    Set-Screen $s
}

$script:Win = New-Object System.Windows.Window
$Win.Title='IT Help Desk - LZFD Karlsruhe (UI TEST)'; $Win.Width=580; $Win.Height=600
$Win.WindowStartupLocation='CenterScreen'; $Win.Background=(C '#f4f4ef')

$outer=New-Object System.Windows.Controls.Grid; $outer.Margin=(T 14)
$r1=New-Object System.Windows.Controls.RowDefinition; $r1.Height='*'
$r2=New-Object System.Windows.Controls.RowDefinition; $r2.Height='Auto'
$outer.RowDefinitions.Add($r1)|Out-Null; $outer.RowDefinitions.Add($r2)|Out-Null

$frame=New-Object System.Windows.Controls.Border; $frame.BorderBrush=(C $Clr.Ink); $frame.BorderThickness=(T 3); $frame.Background=[System.Windows.Media.Brushes]::White
$script:ContentHost=New-Object System.Windows.Controls.ContentControl; $frame.Child=$script:ContentHost
[System.Windows.Controls.Grid]::SetRow($frame,0); $outer.Children.Add($frame)|Out-Null

$bar=New-Object System.Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; $bar.Margin=(T 4,10,0,0)
$blbl=New-Object System.Windows.Controls.TextBlock; $blbl.Text='TEST - simulate next step: '; $blbl.VerticalAlignment='Center'; $blbl.Foreground=(C '#666')
$script:SimCombo=New-Object System.Windows.Controls.ComboBox; $SimCombo.Width=120; $SimCombo.Items.Add('Success')|Out-Null; $SimCombo.Items.Add('Failure')|Out-Null; $SimCombo.SelectedIndex=0
$bar.Children.Add($blbl)|Out-Null; $bar.Children.Add($script:SimCombo)|Out-Null
[System.Windows.Controls.Grid]::SetRow($bar,1); $outer.Children.Add($bar)|Out-Null

$Win.Content=$outer
Show-Login
$Win.ShowDialog() | Out-Null
