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

# 3. Docker login to ECR with a 12-hour token derived from your AWS session.
Write-Host "Logging Docker in to $registry" -ForegroundColor Cyan
Invoke-Native 'ECR login' { aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry }

$services = if ($Service -eq 'all') { @('backend', 'frontend') } else { @($Service) }

foreach ($svc in $services) {
  $repoUrl = $repos.$svc
  $repoName = ($repoUrl -split '/', 2)[1]
  $image = "${repoUrl}:${tag}"

  # 4. Skip if this exact tag is already in ECR (immutable tags can't be overwritten).
  aws ecr describe-images --region $region --repository-name $repoName --image-ids imageTag=$tag 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[$svc] $tag already in ECR, skipping" -ForegroundColor Yellow
    continue
  }

  # 5. Build and push.
  Write-Host "[$svc] Building $image ($Platform)" -ForegroundColor Cyan
  Invoke-Native "[$svc] docker build" { docker build --platform $Platform -t $image "$root/$svc" }

  Write-Host "[$svc] Pushing" -ForegroundColor Cyan
  Invoke-Native "[$svc] docker push" { docker push $image }

  # 6. Wait for the scan-on-push result and summarise it.
  Write-Host "[$svc] Waiting for vulnerability scan" -ForegroundColor Cyan
  aws ecr wait image-scan-complete --region $region --repository-name $repoName --image-id imageTag=$tag
  $counts = aws ecr describe-image-scan-findings --region $region --repository-name $repoName --image-id imageTag=$tag `
    --query 'imageScanFindings.findingSeverityCounts' --output json | ConvertFrom-Json
  if ($counts) {
    Write-Host "[$svc] Scan findings: $(($counts.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')" -ForegroundColor Yellow
  } else {
    Write-Host "[$svc] Scan findings: none" -ForegroundColor Green
  }
}

Write-Host "`nDone. Deploy with image tag: $tag" -ForegroundColor Green
