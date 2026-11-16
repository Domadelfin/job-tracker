<#
.SYNOPSIS
  Build the frontend/backend Docker images and push them to ECR.

.DESCRIPTION
  Uses your short-lived `aws login` session, so no AWS keys are stored anywhere.
  (Keyless GitHub OIDC isn't available: the project's SCP denies iam:*Provider*.)

  Images are tagged with the current git commit SHA. ECR tags are immutable, so
  a tag always maps to exactly one build of exactly one commit.

.EXAMPLE
  ./scripts/push-images.ps1                 # both services
  ./scripts/push-images.ps1 -Service backend
#>
[CmdletBinding()]
param(
  [ValidateSet('all', 'frontend', 'backend')]
  [string]$Service = 'all',

  # Must match the task definition's runtimePlatform (cpuArchitecture X86_64).
  [string]$Platform = 'linux/amd64',

  # Build from uncommitted changes anyway (tag gets a "-dirty" suffix).
  [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Native([string]$What, [scriptblock]$Command) {
  & $Command
  if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)" }
}

# 1. Tag = git commit SHA; refuse to build uncommitted code by default.
$dirty = git -C $root status --porcelain -- frontend backend
$tag = (git -C $root rev-parse --short=7 HEAD).Trim()
if ($dirty) {
  if (-not $AllowDirty) {
    throw "Uncommitted changes in frontend/ or backend/. Commit first (or pass -AllowDirty)."
  }
  $tag = "$tag-dirty-$(Get-Date -Format 'yyyyMMddHHmmss')"
}
Write-Host "Image tag: $tag" -ForegroundColor Cyan

# 2. Check AWS session, then read repo URLs from Terraform (nothing hard-coded).
Invoke-Native 'AWS session check (run `aws login`)' { aws sts get-caller-identity --output text --query Account | Out-Null }
$outputs = terraform -chdir="$root/infra/foundation" output -json | ConvertFrom-Json
$repos = $outputs.ecr_repository_urls.value
$region = $outputs.region.value
$registry = ($repos.backend -split '/')[0]

# 3. ECR credentials for the push, kept in a throwaway Docker config folder.
#    Why not `aws ecr get-login-password | docker login --password-stdin`?
#     - Windows PowerShell 5.1 alters text piped between native programs, so ECR
#       rejects the password (400 Bad Request).
#     - Docker on Windows saves logins in Windows Credential Manager, which can't
#       hold tokens this large (~4 KB from `aws login` sessions).
#    Writing the auth entry directly avoids both. The 12-hour token is deleted in
#    the `finally` block below, so it never lingers on disk.
$token = aws ecr get-login-password --region $region
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Could not get an ECR token (run `aws login`)' }
$engine = (docker context inspect --format '{{.Endpoints.docker.Host}}').Trim() # keep using Docker Desktop's engine
$pushConfig = Join-Path ([IO.Path]::GetTempPath()) ("ecr-push-" + [guid]::NewGuid())
New-Item -ItemType Directory $pushConfig | Out-Null
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("AWS:$token"))
@{ auths = @{ $registry = @{ auth = $auth } } } | ConvertTo-Json -Depth 4 |
  Set-Content -Encoding ascii (Join-Path $pushConfig 'config.json')
Remove-Variable token, auth

function Invoke-WithEcrAuth([scriptblock]$Command) {
  $env:DOCKER_CONFIG = $pushConfig
  $env:DOCKER_HOST = $engine
  try { & $Command } finally { Remove-Item Env:DOCKER_CONFIG, Env:DOCKER_HOST -ErrorAction SilentlyContinue }
}

function Test-ImageTagExists([string]$RepoName) {
  # PowerShell 5.1 turns a native command's stderr into a terminating error when
  # $ErrorActionPreference is Stop, so relax it for this expected "not found".
  $ErrorActionPreference = 'Continue'
  aws ecr describe-images --region $region --repository-name $RepoName --image-ids imageTag=$tag 2>&1 | Out-Null
  return ($LASTEXITCODE -eq 0)
}

$services = if ($Service -eq 'all') { @('backend', 'frontend') } else { @($Service) }

try {
foreach ($svc in $services) {
  $repoUrl = $repos.$svc
  $repoName = ($repoUrl -split '/', 2)[1]
  $image = "${repoUrl}:${tag}"

  # 4. Skip if this exact tag is already in ECR (immutable tags can't be overwritten).
  if (Test-ImageTagExists $repoName) {
    Write-Host "[$svc] $tag already in ECR, skipping" -ForegroundColor Yellow
    continue
  }

  # 5. Build (normal Docker config) and push (temporary ECR credentials).
  Write-Host "[$svc] Building $image ($Platform)" -ForegroundColor Cyan
  # --provenance/--sbom=false: push one plain image manifest. Otherwise Docker
  # pushes an image *index* + untagged children, which ECR basic scanning skips
  # and the "expire untagged" lifecycle rule could delete out from under the tag.
  Invoke-Native "[$svc] docker build" {
    docker build --platform $Platform --provenance=false --sbom=false -t $image "$root/$svc"
  }

  Write-Host "[$svc] Pushing" -ForegroundColor Cyan
  Invoke-WithEcrAuth { Invoke-Native "[$svc] docker push" { docker push $image } }

  # 6. Wait for the scan-on-push result and summarise it.
  Write-Host "[$svc] Waiting for vulnerability scan" -ForegroundColor Cyan
  aws ecr wait image-scan-complete --region $region --repository-name $repoName --image-id imageTag=$tag
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "[$svc] Scan did not complete; check the ECR console for this image"
    continue
  }
  $counts = aws ecr describe-image-scan-findings --region $region --repository-name $repoName --image-id imageTag=$tag `
    --query 'imageScanFindings.findingSeverityCounts' --output json | ConvertFrom-Json
  if ($counts) {
    Write-Host "[$svc] Scan findings: $(($counts.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')" -ForegroundColor Yellow
  } else {
    Write-Host "[$svc] Scan findings: none" -ForegroundColor Green
  }
}
}
finally {
  Remove-Item -Recurse -Force $pushConfig -ErrorAction SilentlyContinue
}

Write-Host "`nDone. Deploy with image tag: $tag" -ForegroundColor Green
