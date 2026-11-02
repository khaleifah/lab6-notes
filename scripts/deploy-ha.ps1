param(
    [string]$WslKeyPath = '~/.ssh/lab6.pem'
)
$ErrorActionPreference = 'Stop'
$ProjectDir = Split-Path $PSScriptRoot -Parent
$AnsibleDir = Join-Path $ProjectDir 'ansible'
Push-Location (Join-Path $ProjectDir 'infra-ha')
try {
    & tofu init
    if ($LASTEXITCODE -ne 0) { throw 'OpenTofu initialization failed.' }
    & tofu validate
    if ($LASTEXITCODE -ne 0) { throw 'OpenTofu validation failed.' }
    & tofu plan
    if ($LASTEXITCODE -ne 0) { throw 'OpenTofu plan failed.' }
    & tofu apply
    if ($LASTEXITCODE -ne 0) { throw 'OpenTofu apply failed or was cancelled.' }
    $NodesJson = & tofu output -json nodes
    if ($LASTEXITCODE -ne 0) { throw 'Could not read instance outputs.' }
    [IO.File]::WriteAllText((Join-Path $AnsibleDir 'nodes.json'), ($NodesJson -join "`n"), [Text.UTF8Encoding]::new($false))
} finally { Pop-Location }

& wsl.exe --cd $AnsibleDir -- python3 make-inventory.py --nodes-file nodes.json --key $WslKeyPath
if ($LASTEXITCODE -ne 0) { throw 'Inventory creation failed. Check WSL and its PEM path.' }
if (-not (Test-Path (Join-Path $AnsibleDir 'secrets.yml'))) {
    & wsl.exe --cd $AnsibleDir -- python3 make-secrets.py
    if ($LASTEXITCODE -ne 0) { throw 'Secret generation failed.' }
}
& wsl.exe --cd $AnsibleDir -- ansible-playbook -i inventory.json site.yml --syntax-check
if ($LASTEXITCODE -ne 0) { throw 'Ansible syntax check failed.' }
& wsl.exe --cd $AnsibleDir -- ansible-playbook -i inventory.json site.yml
if ($LASTEXITCODE -ne 0) { throw 'Ansible configuration failed; inspect the failed task and rerun after fixing it.' }
