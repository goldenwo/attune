# codex/run-hook.ps1 — Windows launcher for the Codex plugin hooks.
#
# Why this exists: Codex spawns a hook command by PATH-resolving its first token. On
# Windows, bare `bash` frequently resolves to C:\Windows\System32\bash.exe (the WSL
# launcher), NOT git-bash — so a `bash <hook>.sh` command never runs the hook. The
# hooks.json `commandWindows` therefore calls this launcher, which resolves git-bash
# deterministically from the on-PATH `git` location and delegates to codex/run-hook.sh
# (the single code path that adapts apply_patch payloads and runs hooks/<hook>.sh).
#
# Stdin is read here and written to the child explicitly so the payload's delivery does
# not depend on the PowerShell host's handle-inheritance rules. Measured 2026-09-07 under
# Codex's real spawn shape (cmd.exe /C, stdin piped, JSON written after spawn) on Windows
# PowerShell 5.1: a plain `& $bash …` child ALSO received every byte, so this is
# belt-and-braces, not a fix — the earlier "PowerShell swallows the payload" note did not
# reproduce. Explicit forwarding stays because it is host-independent and byte-exact.
#
# macOS/Linux never use this — there the hooks.json `command` runs `bash` directly.
param([Parameter(Mandatory = $true)][string]$Hook)

# Plugin root: Codex exports CLAUDE_PLUGIN_ROOT / PLUGIN_ROOT = the install dir.
$root = $env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = $env:PLUGIN_ROOT }
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }   # codex/ -> plugin root
$root = $root -replace '\\', '/'   # git-bash-friendly; avoids backslash-escape issues

# Resolve git-bash: derive from the on-PATH git (…/Git/cmd/git.exe -> …/Git/bin/bash.exe),
# then fall back to common install locations.
$bash = $null
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $cand = Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe'
    if (Test-Path $cand) { $bash = $cand }
}
if (-not $bash) {
    foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe",
                     "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
                     "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($c -and (Test-Path $c)) { $bash = $c; break }
    }
}
if (-not $bash) { exit 0 }   # no git-bash -> silent no-op, never break the session

$launcher = "$root/codex/run-hook.sh"
if (-not (Test-Path $launcher)) { exit 0 }

$env:CLAUDE_PLUGIN_ROOT = $root   # ensure the hook can locate bin/where-am-i etc.

# Read the payload PowerShell already owns, then pipe it to the child ourselves.
$payload = ''
try { $payload = [Console]::In.ReadToEnd() } catch { $payload = '' }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $bash
$psi.Arguments = ('"{0}" "{1}"' -f $launcher, $Hook)
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = $utf8
$psi.StandardErrorEncoding = $utf8
$psi.WorkingDirectory = (Get-Location).Path

$p = [System.Diagnostics.Process]::Start($psi)
$errTask = $p.StandardError.ReadToEndAsync()
$outTask = $p.StandardOutput.ReadToEndAsync()
$stdin = New-Object System.IO.StreamWriter($p.StandardInput.BaseStream, $utf8)
$stdin.Write($payload)
$stdin.Close()
$p.WaitForExit()

$stdout = [Console]::OpenStandardOutput()
$bytes = $utf8.GetBytes($outTask.Result)
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
$stderr = [Console]::OpenStandardError()
$bytes = $utf8.GetBytes($errTask.Result)
$stderr.Write($bytes, 0, $bytes.Length)
$stderr.Flush()
exit $p.ExitCode
