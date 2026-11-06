# Upload all files from D:\git to:
# https://github.com/huynhcongtu0101-cmyk/cdn/tree/main/vodichthienmenh
# Uses GitHub REST API only. No Git or GitHub Desktop required.

$ErrorActionPreference = "Stop"

$SourceFolder = "D:\git"
$Owner = "huynhcongtu0101-cmyk"
$Repo = "cdn"
$Branch = "main"
$DestinationFolder = "vodichthienmenh"
$ApiBase = "https://api.github.com"

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory=$true)][string]$Method,
        [Parameter(Mandatory=$true)][string]$Uri,
        $Payload = $null
    )

    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = $script:Headers
        ErrorAction = "Stop"
    }

    if ($null -ne $Payload) {
        $json = ConvertTo-Json -InputObject $Payload -Depth 100 -Compress
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    return Invoke-RestMethod @params
}

try {
    Clear-Host
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "       GITHUB UPLOADER - D:\git" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw "Khong tim thay thu muc nguon: $SourceFolder"
    }

    Write-Host "Repository : $Owner/$Repo" -ForegroundColor Gray
    Write-Host "Nhanh      : $Branch" -ForegroundColor Gray
    Write-Host "Thu muc dich: $DestinationFolder/" -ForegroundColor Gray
    Write-Host "Nguon      : $SourceFolder" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Can GitHub Personal Access Token co quyen Contents: Read and write." -ForegroundColor Yellow
    $secureToken = Read-Host "Dan GitHub token vao day (khong hien ky tu)" -AsSecureString
    if ($null -eq $secureToken -or $secureToken.Length -eq 0) {
        throw "Chua nhap GitHub token."
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    try {
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    $script:Headers = @{
        Authorization = "Bearer $token"
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "DGit-GitHub-Uploader"
    }
    $token = $null

    Write-Host "`nDang kiem tra quyen truy cap..." -ForegroundColor Cyan
    $null = Invoke-GitHubApi -Method GET -Uri "$ApiBase/repos/$Owner/$Repo"

    $files = @(Get-ChildItem -LiteralPath $SourceFolder -File -Recurse -Force)
    if ($files.Count -eq 0) {
        throw "Thu muc D:\git khong co file nao de upload."
    }

    $tooLarge = @($files | Where-Object { $_.Length -gt 100MB })
    if ($tooLarge.Count -gt 0) {
        $names = ($tooLarge | ForEach-Object { "$($_.FullName) ($([math]::Round($_.Length / 1MB, 1)) MB)" }) -join "`n"
        throw "GitHub REST API khong phu hop voi file lon hon 100 MB. Hay xu ly cac file nay truoc:`n$names"
    }

    Write-Host "Tim thay $($files.Count) file." -ForegroundColor Green
    Write-Host "Dang lay thong tin nhanh main..." -ForegroundColor Cyan

    $ref = Invoke-GitHubApi -Method GET -Uri "$ApiBase/repos/$Owner/$Repo/git/ref/heads/$Branch"
    $parentCommitSha = $ref.object.sha
    $parentCommit = Invoke-GitHubApi -Method GET -Uri "$ApiBase/repos/$Owner/$Repo/git/commits/$parentCommitSha"
    $baseTreeSha = $parentCommit.tree.sha

    $treeItems = @()
    $index = 0

    foreach ($file in $files) {
        $index++
        $relativePath = $file.FullName.Substring($SourceFolder.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
        $repoPath = "$DestinationFolder/$relativePath"

        Write-Progress -Activity "Dang upload file len GitHub" `
            -Status "$index / $($files.Count): $relativePath" `
            -PercentComplete ([int](100 * $index / $files.Count))

        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $base64 = [Convert]::ToBase64String($bytes)

        $blob = Invoke-GitHubApi -Method POST `
            -Uri "$ApiBase/repos/$Owner/$Repo/git/blobs" `
            -Payload ([ordered]@{
                content = $base64
                encoding = "base64"
            })

        $treeItems += [ordered]@{
            path = $repoPath
            mode = "100644"
            type = "blob"
            sha = $blob.sha
        }
    }

    Write-Progress -Activity "Dang upload file len GitHub" -Completed
    Write-Host "`nDang tao commit..." -ForegroundColor Cyan

    $newTree = Invoke-GitHubApi -Method POST `
        -Uri "$ApiBase/repos/$Owner/$Repo/git/trees" `
        -Payload ([ordered]@{
            base_tree = $baseTreeSha
            tree = $treeItems
        })

    $message = "Upload D:\git to $DestinationFolder - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $newCommit = Invoke-GitHubApi -Method POST `
        -Uri "$ApiBase/repos/$Owner/$Repo/git/commits" `
        -Payload ([ordered]@{
            message = $message
            tree = $newTree.sha
            parents = @($parentCommitSha)
        })

    $updatedRef = Invoke-GitHubApi -Method PATCH `
        -Uri "$ApiBase/repos/$Owner/$Repo/git/refs/heads/$Branch" `
        -Payload ([ordered]@{
            sha = $newCommit.sha
            force = $false
        })

    Write-Host ""
    Write-Host "UPLOAD THANH CONG!" -ForegroundColor Green
    Write-Host "So file: $($files.Count)" -ForegroundColor Green
    Write-Host "Commit : $($newCommit.sha)" -ForegroundColor Gray
    Write-Host "Link   : https://github.com/$Owner/$Repo/tree/$Branch/$DestinationFolder" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "UPLOAD THAT BAI:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message -ForegroundColor DarkRed
    }
    Write-Host ""
    Write-Host "Kiem tra token, quyen Contents: Read and write, nhanh main va ket noi Internet." -ForegroundColor Yellow
}
finally {
    if ($script:Headers) {
        $script:Headers.Authorization = $null
    }
}

Read-Host "Nhan Enter de dong cua so"
