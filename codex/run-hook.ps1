# codex/run-hook.ps1 - Windows launcher for the Codex plugin hooks.
#
# Why this exists: Codex spawns a hook command by PATH-resolving its first token. On
# Windows, bare `bash` frequently resolves to C:\Windows\System32\bash.exe (the WSL
# launcher), NOT git-bash - so a `bash <hook>.sh` command never runs the hook. The
# hooks.json `commandWindows` therefore calls this launcher, which resolves git-bash
# deterministically from the on-PATH `git` location and delegates to codex/run-hook.sh
# (the single code path that adapts apply_patch payloads and runs hooks/<hook>.sh).
#
# Transport is BYTES, never text. The payload is copied from stdin to the child and the
# child's stdout/stderr back out as raw bytes, so no console code page ever decodes them.
# Measured 2026-09-24 (codex 0.155.1, TUI and exec, from a fresh Windows Terminal tab where
# chcp reports 437): Codex writes exact UTF-8, but every hook child inherits input code page
# 437 - a PowerShell profile that sets [Console]::OutputEncoding moves only the OUTPUT code
# page - and the previous [Console]::In.ReadToEnd() turned a prompt's non-ASCII text into
# mojibake before any hook saw it. At code page 65001 it prepended a UTF-8 BOM instead (see
# below). codex/run-hook.test.ps1 pins both directions under both code pages.
#
# Codex runs this through its session shell (powershell.exe -NoProfile -Command "<cmd>",
# measured) or cmd.exe /C; both hand stdin/stdout/stderr through to this process unchanged.
#
# macOS/Linux never use this - there the hooks.json `command` runs `bash` directly.
param([Parameter(Mandatory = $true)][string]$Hook)

# Plugin root: Codex exports CLAUDE_PLUGIN_ROOT / PLUGIN_ROOT = the install dir.
$root = $env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = $env:PLUGIN_ROOT }
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }   # codex/ -> plugin root
$root = $root -replace '\\', '/'   # git-bash-friendly; avoids backslash-escape issues

# Resolve git-bash: derive from the on-PATH git (.../Git/cmd/git.exe -> .../Git/bin/bash.exe),
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

# The payload, as the bytes Codex wrote.
$in = New-Object System.IO.MemoryStream
try { [Console]::OpenStandardInput().CopyTo($in) } catch { }
$payload = $in.ToArray()

# Process.Start (.NET Framework) wraps the child's stdin in a writer that uses
# [Console]::InputEncoding and flushes that encoding's preamble at once: at console code
# page 65001 the hook received EF BB BF ahead of the payload even when only raw bytes were
# written (measured 2026-09-24). Setting the SAME code page with a BOM-less UTF-8 encoding
# leaves the console untouched and drops the preamble. Only UTF-8 has one among console
# code pages; with no console attached the encoding is ANSI and this is skipped.
try {
    if ([Console]::InputEncoding.GetPreamble().Length -gt 0) {
        [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
} catch { }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $bash
$psi.Arguments = ('"{0}" "{1}"' -f $launcher, $Hook)
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.WorkingDirectory = (Get-Location).Path

$p = [System.Diagnostics.Process]::Start($psi)
# Drain stdout/stderr before feeding stdin: a hook that writes more than a pipe buffer
# before it reads would otherwise deadlock against a large payload.
$out = New-Object System.IO.MemoryStream
$err = New-Object System.IO.MemoryStream
$outCopy = $p.StandardOutput.BaseStream.CopyToAsync($out)
$errCopy = $p.StandardError.BaseStream.CopyToAsync($err)
$childIn = $p.StandardInput.BaseStream
try { $childIn.Write($payload, 0, $payload.Length) } catch { }   # a hook may exit without reading
try { $childIn.Close() } catch { }
$p.WaitForExit()
$outCopy.Wait()
$errCopy.Wait()

$bytes = $out.ToArray()
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
$bytes = $err.ToArray()
$stderr = [Console]::OpenStandardError()
$stderr.Write($bytes, 0, $bytes.Length)
$stderr.Flush()
exit $p.ExitCode
